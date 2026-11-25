import 'dart:async';
import 'dart:convert';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/models/model_test.dart';
import 'package:academy_management/repositories/model_test_repository.dart';
import 'package:academy_management/services/bengali_numbers.dart';
import 'package:academy_management/services/model_test_timer.dart'
    show formatDuration;
import 'package:academy_management/views/exams/model_test_result_view.dart';
import 'package:academy_management/views/exams/model_test_start_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Official test-taking flow: all questions on one scrollable page, a live
/// second-by-second AppBar countdown, and answers synced through the existing
/// SECURITY DEFINER RPCs. Marks/attempts are still written only by the backend.
class ModelTestTakingView extends StatefulWidget {
  final ModelTest test;
  final String studentId;

  /// Rejoin path: an active `in_progress` attempt is resumed silently. The
  /// start confirmation is only for fresh official starts (and practice).
  final bool skipConfirmation;

  const ModelTestTakingView({
    super.key,
    required this.test,
    required this.studentId,
    this.skipConfirmation = false,
  });

  @override
  State<ModelTestTakingView> createState() => _ModelTestTakingViewState();
}

class _ModelTestTakingViewState extends State<ModelTestTakingView>
    with WidgetsBindingObserver {
  final _repository = ModelTestRepository();

  bool _confirmed = false;
  bool _isLoading = true;
  String? _error;
  ModelTestSession? _session;

  // An absolute deadline plus a real 1-second ticker: rebuilding every tick
  // keeps the AppBar countdown moving even while the student is scrolling.
  Timer? _tickTimer;
  DateTime? _deadline;
  bool _expiryHandled = false;

  final Map<String, String> _answers = <String, String>{};
  final Set<String> _review = <String>{};
  final Map<String, Timer> _saveDebounce = <String, Timer>{};
  final Set<String> _pendingPush = <String>{};
  final Map<int, GlobalKey> _questionKeys = <int, GlobalKey>{};

  bool _submitting = false;
  bool _syncWarning = false;

  static const _cachePrefix = 'model_test_answers_';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.skipConfirmation) {
      // The card already confirmed that an active live attempt exists. Going
      // straight to the RPC resumes it without showing the start dialog.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _confirmed = true);
        unawaited(_bootstrap());
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askToStart());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    for (final timer in _saveDebounce.values) {
      timer.cancel();
    }
    _saveDebounce.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _confirmed) {
      unawaited(_resync());
    }
  }

  Future<void> _askToStart() async {
    final duration = widget.test.durationMinutes > 0
        ? widget.test.durationMinutes
        : 30;
    final questionCount = widget.test.questionCount > 0
        ? widget.test.questionCount
        : widget.test.questions.length;
    final ok = await showModelTestStartDialog(
      examTitle: widget.test.examTitle,
      subjectName: widget.test.subjectName,
      questionCount: questionCount,
      durationMinutes: duration,
      marksPerQuestion: widget.test.marksPerQuestion,
      negativeMarks: widget.test.negativeMarks,
      practice: false,
    );
    if (!mounted) return;
    if (!ok) {
      Get.back();
      return;
    }
    setState(() => _confirmed = true);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final session = await _repository.startAttempt(widget.test.id);
      if (!mounted) return;
      await _applySession(session);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ModelTestRepository.friendlyError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _applySession(ModelTestSession session) async {
    final cached = await _readCache(session.attempt.id);
    final merged = <String, String>{...session.answers};
    final pending = <String>{};
    cached.forEach((key, value) {
      if (value.isNotEmpty && merged[key] != value) {
        merged[key] = value;
        pending.add(key);
      }
    });

    if (!mounted) return;
    setState(() {
      _session = session;
      _answers
        ..clear()
        ..addAll(merged);
      _pendingPush
        ..clear()
        ..addAll(pending);
      _review.clear();
      _questionKeys.clear();
      _isLoading = false;
      _error = null;
    });

    _startTicking(
      session.attempt.deadlineAt ??
          DateTime.now().add(widget.test.attemptDuration),
    );
    await _writeCache(session.attempt.id);
    if (pending.isNotEmpty) unawaited(_flushPending());
  }

  // ---------------------------------------------------------------------------
  // Countdown
  // ---------------------------------------------------------------------------

  void _startTicking(DateTime deadline) {
    _tickTimer?.cancel();
    _deadline = deadline;
    _expiryHandled = false;
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _onTick();
  }

  Duration get _remaining {
    final deadline = _deadline;
    if (deadline == null) return Duration.zero;
    final diff = deadline.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  void _onTick() {
    if (!mounted) return;
    if (_remaining <= Duration.zero &&
        !_expiryHandled &&
        !_submitting &&
        _session != null) {
      _expiryHandled = true;
      unawaited(_submit(auto: true));
    }
    // Rebuild on every tick so the AppBar chip never freezes mid-countdown.
    setState(() {});
  }

  Widget _buildTimerChip() {
    final remaining = _remaining;
    final low = remaining.inMinutes < 5;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: low ? Colors.red.shade700 : Colors.white24,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(low ? Icons.warning_amber : Icons.timer, size: 15),
          const SizedBox(width: 5),
          Text(
            bn(formatDuration(remaining)),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Answers (local cache + official RPC)
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _readCache(String attemptId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$attemptId');
      if (raw == null || raw.isEmpty) return <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeCache(String attemptId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cachePrefix$attemptId', jsonEncode(_answers));
    } catch (_) {
      // Cache is a best-effort safety net; Supabase remains authoritative.
    }
  }

  Future<void> _clearCache(String attemptId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cachePrefix$attemptId');
    } catch (_) {}
  }

  void _selectOption(String questionId, String option) {
    if (_submitting) return;
    setState(() {
      if (_answers[questionId] == option) {
        _answers.remove(questionId);
      } else {
        _answers[questionId] = option;
      }
      _pendingPush.add(questionId);
    });
    unawaited(_writeCache(_session!.attempt.id));
    _saveDebounce[questionId]?.cancel();
    _saveDebounce[questionId] = Timer(const Duration(milliseconds: 450), () {
      unawaited(_pushAnswer(questionId));
    });
  }

  Future<void> _pushAnswer(String questionId) async {
    final session = _session;
    if (session == null) return;
    final selected = _answers[questionId];
    try {
      await _repository.saveAnswer(
        attemptId: session.attempt.id,
        questionId: questionId,
        selectedOption: selected,
      );
      _pendingPush.remove(questionId);
      if (mounted) setState(() => _syncWarning = false);
    } catch (_) {
      _pendingPush.add(questionId);
      if (mounted) setState(() => _syncWarning = true);
    }
  }

  Future<void> _flushPending() async {
    final ids = _pendingPush.toList();
    for (final id in ids) {
      await _pushAnswer(id);
    }
  }

  Future<void> _resync() async {
    final session = _session;
    if (session == null || _submitting) return;
    if (_remaining <= Duration.zero) {
      await _submit(auto: true);
      return;
    }
    try {
      final fresh = await _repository.startAttempt(widget.test.id);
      if (!mounted) return;
      await _applySession(fresh);
    } catch (_) {
      if (mounted) setState(() => _syncWarning = true);
    }
  }

  Future<void> _submit({required bool auto}) async {
    final session = _session;
    if (session == null || _submitting) return;
    setState(() => _submitting = true);
    // Flush what can be flushed, but never block submission on the network.
    for (final timer in _saveDebounce.values) {
      timer.cancel();
    }
    _saveDebounce.clear();
    await _flushPending();
    _tickTimer?.cancel();

    try {
      final result = await _repository.submitAttempt(
        session.attempt.id,
        auto: auto,
      );
      await _clearCache(session.attempt.id);
      if (!mounted) return;
      await Get.off(
        () => ModelTestResultView(
          attemptId: result['attempt_id']?.toString() ?? session.attempt.id,
          academyId: widget.test.academyId,
          studentId: widget.studentId,
          test: widget.test,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _syncWarning = true;
        _error = ModelTestRepository.friendlyError(e);
      });
    }
  }

  void _confirmSubmit() {
    final answered = _answers.values.where((v) => v.isNotEmpty).length;
    final total = _session?.questions.length ?? 0;
    Get.dialog(
      AlertDialog(
        title: const Text('পরীক্ষা জমা দিন'),
        content: Text(
          answered < total
              ? 'আপনি এখনো ${bn(total)} টির মধ্যে ${bn(answered)} টি প্রশ্নের উত্তর দিয়েছেন। অবশিষ্ট প্রশ্নগুলো উত্তরহীন হিসেবে গণনা হবে। জমা দিতে চান?'
              : 'আপনি সব ${bn(total)} টি প্রশ্নের উত্তর দিয়েছেন। এখন জমা দিতে চান?',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('ফিরে যান'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () {
              Get.back();
              unawaited(_submit(auto: false));
            },
            child: const Text(
              'হ্যাঁ, জমা দিন',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  GlobalKey _keyFor(int index) =>
      _questionKeys.putIfAbsent(index, () => GlobalKey());

  void _showQuestionSheet(List<ModelTestQuestion> questions) {
    Get.bottomSheet(
      SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'প্রশ্ন তালিকা (${bn(questions.length)})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(questions.length, (index) {
                  final q = questions[index];
                  final answered = (_answers[q.id] ?? '').isNotEmpty;
                  final marked = _review.contains(q.id);
                  return SizedBox(
                    width: 48,
                    height: 48,
                    child: InkWell(
                      onTap: () {
                        Get.back();
                        final context = _keyFor(index).currentContext;
                        if (context != null) {
                          Scrollable.ensureVisible(
                            context,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            alignment: 0.08,
                          );
                        }
                      },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: answered
                              ? Colors.teal.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: marked
                                ? Colors.amber
                                : answered
                                ? Colors.teal
                                : Colors.grey.shade300,
                            width: marked ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          bn(index + 1),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: answered
                                ? Colors.teal.shade800
                                : Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_confirmed) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('মডেল টেস্ট')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('মডেল টেস্ট')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 56,
                  color: AppTheme.errorOf(context),
                ),
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.mutedOf(context)),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _bootstrap,
                  icon: const Icon(Icons.refresh),
                  label: const Text('আবার চেষ্টা করুন'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final session = _session!;
    final questions = session.questions;
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.test.examTitle)),
        body: const Center(child: Text('এই পরীক্ষার কোনো প্রশ্ন পাওয়া যায়নি।')),
      );
    }

    final answered = _answers.values.where((v) => v.isNotEmpty).length;
    return Scaffold(
      backgroundColor: AppTheme.surfaceOf(context),
      appBar: AppBar(
        title: Text(
          widget.test.examTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
        foregroundColor: Colors.white,
        actions: [
          _buildTimerChip(),
          IconButton(
            tooltip: 'প্রশ্ন তালিকা',
            onPressed: () => _showQuestionSheet(questions),
            icon: const Icon(Icons.grid_view),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_syncWarning) _buildSyncWarning(),
            _buildProgressStrip(answered, questions.length),
            LinearProgressIndicator(
              value: answered / questions.length,
              backgroundColor: AppTheme.borderOf(context),
              color: Colors.teal,
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                itemCount: questions.length + 1,
                itemBuilder: (context, index) {
                  if (index == questions.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'সব প্রশ্নের উত্তর দিয়ে নিচের বাটনে জমা দিন।',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    );
                  }
                  return _buildQuestionCard(questions[index], index);
                },
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncWarning() => Container(
    width: double.infinity,
    color: AppTheme.tileOf(context, Colors.orange),
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
    child: Text(
      'কিছু উত্তর সংরক্ষণ হয়নি। সংযোগ ফিরলে আবার চেষ্টা করা হবে।',
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        color: AppTheme.tileInkOf(context, Colors.orange),
      ),
    ),
  );

  Widget _buildProgressStrip(int answered, int total) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
    child: Row(
      children: [
        Icon(Icons.check_circle_outline, size: 15, color: Colors.teal.shade700),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'উত্তর দেওয়া হয়েছে: ${bn(answered)} / ${bn(total)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.inkOf(context),
            ),
          ),
        ),
        if (_review.isNotEmpty)
          Text(
            '${bn(_review.length)} চিহ্নিত',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.amber),
          ),
      ],
    ),
  );

  Widget _buildQuestionCard(ModelTestQuestion question, int index) {
    final marked = _review.contains(question.id);
    return Card(
      key: _keyFor(index),
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.tileOf(context, Colors.indigo),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${bn(index + 1)}.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.tileInkOf(context, Colors.indigo),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    question.question,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkOf(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(question.options.length, (optionIndex) {
              return _buildOption(question, optionIndex);
            }),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onPressed: () => setState(() {
                  if (marked) {
                    _review.remove(question.id);
                  } else {
                    _review.add(question.id);
                  }
                }),
                icon: Icon(
                  marked ? Icons.bookmark : Icons.bookmark_border,
                  size: 16,
                ),
                label: Text(
                  marked ? 'চিহ্নিত' : 'চিহ্নিত করুন',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(ModelTestQuestion question, int optionIndex) {
    final key = String.fromCharCode(65 + optionIndex);
    final selected = _answers[question.id] == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _selectOption(question.id, key),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.tileOf(context, Colors.teal)
                : AppTheme.surfaceOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.teal : AppTheme.borderOf(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: selected
                    ? Colors.teal
                    : AppTheme.altSurfaceOf(context),
                child: Text(
                  key,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : AppTheme.mutedOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  question.options[optionIndex].isEmpty
                      ? '—'
                      : question.options[optionIndex],
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkOf(context),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: Colors.teal, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() => Container(
    decoration: BoxDecoration(
      color: AppTheme.surfaceOf(context),
      border: Border(top: BorderSide(color: AppTheme.borderOf(context))),
    ),
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    child: Row(
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () {
            final questions =
                _session?.questions ?? const <ModelTestQuestion>[];
            if (questions.isNotEmpty) _showQuestionSheet(questions);
          },
          icon: const Icon(Icons.grid_view, size: 16),
          label: const Text(
            'প্রশ্ন তালিকা',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            onPressed: _submitting ? null : _confirmSubmit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send, size: 16),
            label: Text(
              _submitting ? 'জমা হচ্ছে…' : 'পরীক্ষা জমা দিন',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    ),
  );
}
