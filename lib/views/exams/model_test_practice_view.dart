import 'dart:async';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/models/model_test.dart';
import 'package:academy_management/services/bengali_numbers.dart';
import 'package:academy_management/services/model_test_timer.dart'
    show formatDuration;
import 'package:academy_management/views/exams/model_test_start_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Offline-only practice mode for tests whose official window has closed.
///
/// This view deliberately has **no** Supabase client and performs no RPC or
/// table writes: answers, marks, timer and review stay in memory only, so
/// nothing can reach `model_test_attempts`, `model_test_answers`, results or
/// leaderboards.
class ModelTestPracticeView extends StatefulWidget {
  final ModelTest test;

  const ModelTestPracticeView({super.key, required this.test});

  @override
  State<ModelTestPracticeView> createState() => _ModelTestPracticeViewState();
}

class _ModelTestPracticeViewState extends State<ModelTestPracticeView> {
  bool _confirmed = false;

  Timer? _tickTimer;
  DateTime? _deadline;
  bool _expiryHandled = false;

  final Map<String, String> _answers = <String, String>{};
  final Set<String> _review = <String>{};
  final Map<int, GlobalKey> _questionKeys = <int, GlobalKey>{};
  bool _showReview = false;

  List<ModelTestQuestion> get _questions => widget.test.questions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askToStart());
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _askToStart() async {
    final duration = widget.test.durationMinutes > 0
        ? widget.test.durationMinutes
        : 30;
    final questionCount = widget.test.questionCount > 0
        ? widget.test.questionCount
        : _questions.length;
    final ok = await showModelTestStartDialog(
      examTitle: widget.test.examTitle,
      subjectName: widget.test.subjectName,
      questionCount: questionCount,
      durationMinutes: duration,
      marksPerQuestion: widget.test.marksPerQuestion,
      negativeMarks: widget.test.negativeMarks,
      practice: true,
    );
    if (!mounted) return;
    if (!ok) {
      Get.back();
      return;
    }
    // Practice gets the full configured duration; it is not capped by the
    // (already finished) official scheduling window.
    final practiceDuration = widget.test.durationMinutes > 0
        ? Duration(minutes: widget.test.durationMinutes)
        : const Duration(minutes: 30);
    setState(() => _confirmed = true);
    _startTicking(DateTime.now().add(practiceDuration));
  }

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
    if (_remaining <= Duration.zero && !_expiryHandled) {
      _expiryHandled = true;
      _tickTimer?.cancel();
      setState(() => _showReview = true);
      return;
    }
    // Rebuild on every tick so the AppBar countdown never freezes.
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

  int get _correctCount => _questions
      .where(
        (q) =>
            _answers[q.id] != null &&
            _answers[q.id]!.toUpperCase() == q.correctOption.toUpperCase(),
      )
      .length;

  int get _wrongCount => _questions
      .where(
        (q) =>
            _answers[q.id] != null &&
            _answers[q.id]!.toUpperCase() != q.correctOption.toUpperCase(),
      )
      .length;

  double get _score {
    final perQuestion = widget.test.marksPerQuestion > 0
        ? widget.test.marksPerQuestion
        : 1;
    return (_correctCount * perQuestion -
            _wrongCount * widget.test.negativeMarks)
        .clamp(0, double.infinity)
        .toDouble();
  }

  double get _totalMarks {
    final perQuestion = widget.test.marksPerQuestion > 0
        ? widget.test.marksPerQuestion
        : 1;
    final calculated = (_questions.length * perQuestion).toDouble();
    return calculated > 0 ? calculated : widget.test.totalMarks;
  }

  double get _percentage =>
      _totalMarks > 0 ? (_score / _totalMarks * 100).clamp(0, 100) : 0;

  void _select(String questionId, String option) {
    setState(() {
      if (_answers[questionId] == option) {
        _answers.remove(questionId);
      } else {
        _answers[questionId] = option;
      }
    });
  }

  void _confirmFinish() {
    final answered = _answers.values.where((v) => v.isNotEmpty).length;
    Get.dialog(
      AlertDialog(
        title: const Text('অনুশীলন শেষ করুন?'),
        content: Text(
          answered < _questions.length
              ? 'আপনি ${bn(_questions.length)} টির মধ্যে ${bn(answered)} টি প্রশ্নের উত্তর দিয়েছেন। ফলাফল দেখতে চান?'
              : 'আপনি সব ${bn(_questions.length)} টি প্রশ্নের উত্তর দিয়েছেন। ফলাফল দেখতে চান?',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('ফিরে যান'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Get.back();
              _tickTimer?.cancel();
              setState(() => _showReview = true);
            },
            child: const Text(
              'ফলাফল দেখুন',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  GlobalKey _keyFor(int index) =>
      _questionKeys.putIfAbsent(index, () => GlobalKey());

  void _showQuestionSheet() {
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
                'প্রশ্ন তালিকা (${bn(_questions.length)})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_questions.length, (index) {
                  final q = _questions[index];
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
                              ? Colors.orange.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: marked
                                ? Colors.amber
                                : answered
                                ? Colors.orange
                                : Colors.grey.shade300,
                            width: marked ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          bn(index + 1),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: answered
                                ? Colors.orange.shade900
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
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('অনুশীলন মোড')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'এই পরীক্ষার প্রশ্নগুলো পাওয়া যায়নি, তাই অনুশীলন করা যাচ্ছে না।',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (_showReview) return _buildReviewPage();

    final answered = _answers.values.where((v) => v.isNotEmpty).length;
    return Scaffold(
      backgroundColor: AppTheme.surfaceOf(context),
      appBar: AppBar(
        title: Text(
          'অনুশীলন • ${widget.test.examTitle}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
        actions: [
          _buildTimerChip(),
          IconButton(
            tooltip: 'প্রশ্ন তালিকা',
            onPressed: _showQuestionSheet,
            icon: const Icon(Icons.grid_view),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildNotice(),
            _buildProgressStrip(answered),
            LinearProgressIndicator(
              value: answered / _questions.length,
              backgroundColor: AppTheme.borderOf(context),
              color: Colors.orange,
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                itemCount: _questions.length + 1,
                itemBuilder: (context, index) {
                  if (index == _questions.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'এই উত্তরগুলো কোথাও সংরক্ষণ হবে না।',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    );
                  }
                  return _buildQuestionCard(_questions[index], index);
                },
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildNotice() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    color: AppTheme.tileOf(context, Colors.orange),
    child: Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 15,
          color: AppTheme.tileInkOf(context, Colors.orange),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'শুধু অনুশীলনের জন্য • ফলাফলে যুক্ত হবে না',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.tileInkOf(context, Colors.orange),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildProgressStrip(int answered) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 9, 16, 8),
    child: Row(
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 15,
          color: Colors.orange.shade800,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'উত্তর দেওয়া হয়েছে: ${bn(answered)} / ${bn(_questions.length)}',
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
            style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
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
                    color: AppTheme.tileOf(context, Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${bn(index + 1)}.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.tileInkOf(context, Colors.orange),
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
                  color: Colors.orange,
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
        onTap: () => _select(question.id, key),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.tileOf(context, Colors.orange)
                : AppTheme.surfaceOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.orange : AppTheme.borderOf(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: selected
                    ? Colors.orange
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
                const Icon(Icons.check_circle, color: Colors.orange, size: 18),
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
          onPressed: _showQuestionSheet,
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
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            onPressed: _confirmFinish,
            icon: const Icon(Icons.fact_check, size: 16),
            label: const Text(
              'ফলাফল দেখুন',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildReviewPage() => Scaffold(
    backgroundColor: AppTheme.altSurfaceOf(context),
    appBar: AppBar(
      title: const Text(
        'অনুশীলন ফলাফল',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      backgroundColor: Colors.orange.shade800,
      foregroundColor: Colors.white,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 88),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.tileOf(context, Colors.orange),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'অনুশীলন ফলাফল',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.tileInkOf(context, Colors.orange),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'এই ফলাফল কোথাও সংরক্ষণ বা যোগ করা হয়নি।',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.tileInkOf(context, Colors.orange),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _reviewChip('স্কোর', bnNum(_score)),
                  _reviewChip('মোট', bnNum(_totalMarks)),
                  _reviewChip(
                    'শতাংশ',
                    '${bn(_percentage.toStringAsFixed(1))}%',
                  ),
                  _reviewChip('সঠিক', bn(_correctCount)),
                  _reviewChip('ভুল', bn(_wrongCount)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            _tickTimer?.cancel();
            setState(() => _showReview = false);
          },
          icon: const Icon(Icons.quiz_outlined, size: 16),
          label: const Text(
            'প্রশ্নে ফিরে যান',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () =>
              Get.off(() => ModelTestPracticeView(test: widget.test)),
          icon: const Icon(Icons.replay, size: 16),
          label: const Text(
            'নতুন করে অনুশীলন করুন',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(_questions.length, (index) {
          final q = _questions[index];
          final chosen = _answers[q.id];
          final isCorrect =
              chosen != null && chosen.toUpperCase() == q.correctOption;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppTheme.borderOf(context)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        chosen == null
                            ? Icons.help_outline
                            : isCorrect
                            ? Icons.check_circle
                            : Icons.cancel,
                        color: chosen == null
                            ? Colors.grey
                            : isCorrect
                            ? Colors.green
                            : Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${bn(index + 1)}. ${q.question}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.inkOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _reviewChip(
                        'আপনার উত্তর',
                        chosen == null
                            ? 'উত্তর দেননি'
                            : '$chosen. ${q.optionText(chosen)}',
                      ),
                      _reviewChip(
                        'সঠিক উত্তর',
                        q.correctOption.isEmpty
                            ? 'অজানা'
                            : '${q.correctOption}. ${q.optionText(q.correctOption)}',
                      ),
                    ],
                  ),
                  if (q.explanation.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'ব্যাখ্যা: ${q.explanation}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.mutedOf(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    ),
  );

  Widget _reviewChip(String label, String value) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 240),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.altSurfaceOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: Text(
        '$label: $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.inkOf(context),
        ),
      ),
    ),
  );
}
