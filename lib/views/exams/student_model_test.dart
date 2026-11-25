import 'dart:async';

import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/models/model_test.dart';
import 'package:academy_management/models/student_model_test_progress.dart';
import 'package:academy_management/repositories/model_test_repository.dart';
import 'package:academy_management/services/ad_service.dart';
import 'package:academy_management/services/bengali_numbers.dart';
import 'package:academy_management/services/model_test_reminder_service.dart';
import 'package:academy_management/views/exams/model_test_reminder_sheet.dart';
import 'package:academy_management/views/exams/model_test_practice_view.dart';
import 'package:academy_management/views/exams/model_test_result_view.dart';
import 'package:academy_management/views/exams/student_progress_details_view.dart';
import 'package:academy_management/views/exams/model_test_taking_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Student model-test home: live tests, real attempts, real results and
/// smart reminders for upcoming tests.
class StudentModelTestView extends StatefulWidget {
  final String academyId;
  final String className;
  final String studentId;
  final String? studentName;
  final String? studentRoll;

  /// Optional deep link from a `model_test` push notification (target_id).
  final String? initialTestId;

  const StudentModelTestView({
    super.key,
    required this.academyId,
    required this.className,
    required this.studentId,
    this.studentName,
    this.studentRoll,
    this.initialTestId,
  });

  @override
  State<StudentModelTestView> createState() => _StudentModelTestViewState();
}

class _StudentModelTestViewState extends State<StudentModelTestView>
    with WidgetsBindingObserver {
  final _repository = ModelTestRepository();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _error;
  List<ModelTest> _tests = <ModelTest>[];
  List<ModelTestAttempt> _attempts = <ModelTestAttempt>[];
  StudentModelTestProgress _progress = StudentModelTestProgress.empty();
  String? _selectedSubject;

  RealtimeChannel? _channel;
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  bool _deepLinked = false;

  List<TestReminder> _reminders = <TestReminder>[];
  Timer? _reminderTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _subscribe();
    _loadReminders();
    _reminderTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_checkDueReminders());
    });
    _bannerAd = AdService.createBannerAd()
      ..load().then((_) {
        if (mounted) setState(() => _isBannerAdLoaded = true);
      });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderTicker?.cancel();
    _channel?.unsubscribe();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_load());
      unawaited(_loadReminders());
      unawaited(_checkDueReminders());
    }
  }

  Future<void> _loadReminders() async {
    final reminders = await ModelTestReminderService.load(
      academyId: widget.academyId,
      studentId: widget.studentId,
    );
    if (!mounted) return;
    setState(() => _reminders = reminders);
  }

  Future<void> _checkDueReminders() async {
    if (!mounted || widget.academyId.isEmpty || widget.studentId.isEmpty) {
      return;
    }
    final due = await ModelTestReminderService.dueNow(
      academyId: widget.academyId,
      studentId: widget.studentId,
    );
    for (final reminder in due) {
      await ModelTestReminderService.markTriggered(
        academyId: widget.academyId,
        studentId: widget.studentId,
        testId: reminder.testId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'আসন্ন পরীক্ষা: ${reminder.testTitle} — শুরু ${formatLocal(reminder.startAt)}',
          ),
          backgroundColor: Colors.indigo,
          duration: const Duration(seconds: 6),
        ),
      );
    }
    if (due.isNotEmpty) await _loadReminders();
  }

  void _showReminderSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ModelTestReminderSheet(
        academyId: widget.academyId,
        studentId: widget.studentId,
        tests: _tests,
        onChanged: _loadReminders,
      ),
    );
  }

  Future<void> _toggleQuickReminder(ModelTest test) async {
    final existing = _reminders
        .where((item) => item.testId == test.id)
        .toList();
    if (existing.isNotEmpty) {
      await ModelTestReminderService.remove(
        academyId: widget.academyId,
        studentId: widget.studentId,
        testId: test.id,
      );
      if (mounted) {
        Get.snackbar(
          'রিমাইন্ডার বাতিল',
          '${test.examTitle} এর রিমাইন্ডার বাতিল করা হয়েছে।',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      }
    } else {
      final result = await ModelTestReminderService.set(
        academyId: widget.academyId,
        studentId: widget.studentId,
        testId: test.id,
        testTitle: test.examTitle,
        startAt: test.startAt ?? DateTime.now(),
        minutesBefore: 30,
      );
      if (mounted) {
        Get.snackbar(
          result.saved ? 'রিমাইন্ডার সক্রিয়' : 'তথ্য',
          result.message,
          backgroundColor: result.saved ? Colors.teal : Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      }
    }
    await _loadReminders();
  }

  void _subscribe() {
    if (widget.academyId.trim().isEmpty) return;
    try {
      _channel = _supabase
          .channel(
            'student-model-tests-${widget.academyId}-${widget.studentId}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'exam_schedules',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'academy_id',
              value: widget.academyId,
            ),
            callback: (_) => unawaited(_load()),
          )
          .subscribe();
    } catch (_) {
      // Realtime is optional; pull-to-refresh and on-resume reload still work.
    }
  }

  Future<void> _load() async {
    if (widget.academyId.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'প্রতিষ্ঠানের তথ্য পাওয়া যায়নি। অনুগ্রহ করে আবার লগইন করুন।';
        });
      }
      return;
    }
    try {
      final tests = await _repository.fetchTests(
        academyId: widget.academyId,
        className: widget.className,
      );
      final attempts = await _repository.fetchAttempts(
        academyId: widget.academyId,
        studentId: widget.studentId,
      );

      // Progress/ranks are aggregate-only and optional: if the RPC has not
      // been deployed yet, the UI still shows accurate local submitted stats.
      StudentModelTestProgress progress;
      try {
        progress = await _repository.fetchStudentProgress(
          academyId: widget.academyId,
          className: widget.className,
        );
      } catch (_) {
        progress = StudentModelTestProgress.empty();
      }
      if (!progress.hasResults && attempts.any((item) => item.isSubmitted)) {
        progress = _fallbackProgress(attempts, tests);
      }

      if (!mounted) return;
      setState(() {
        // Defence in depth: only published (including time-over) and expired
        // tests may ever reach a student. Drafts and cancelled tests are never
        // shown, even if the backend RLS policy is older than this client.
        _tests = tests
            .where(
              (test) =>
                  !test.isDraft &&
                  !test.isCancelled &&
                  (test.isPublished || test.isExpired),
            )
            .toList();
        _attempts = attempts;
        _progress = progress;
        _syncSelectedSubject(progress);
        _error = null;
        _isLoading = false;
      });
      _maybeOpenDeepLinkedTest();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ModelTestRepository.friendlyError(e);
        _isLoading = false;
      });
    }
  }

  void _maybeOpenDeepLinkedTest() {
    if (_deepLinked) return;
    final id = widget.initialTestId;
    if (id == null || id.isEmpty) return;
    ModelTest? test;
    for (final item in _tests) {
      if (item.id == id) {
        test = item;
        break;
      }
    }
    if (test == null) return;
    _deepLinked = true;
    unawaited(_openTest(test));
  }

  List<ModelTestAttempt> _attemptsFor(String testId) =>
      _attempts.where((item) => item.testId == testId).toList();

  /// Only a still-live official attempt can be resumed directly. An attempt
  /// whose personal deadline has passed must be finalised by the backend.
  ModelTestAttempt? _activeAttemptFor(String testId) {
    final now = DateTime.now();
    final active =
        _attemptsFor(testId).where((item) {
          if (!item.isInProgress) return false;
          final deadline = item.deadlineAt;
          return deadline == null || deadline.isAfter(now);
        }).toList()..sort((a, b) {
          final startA = a.startedAt ?? DateTime(0);
          final startB = b.startedAt ?? DateTime(0);
          return startB.compareTo(startA);
        });
    return active.isEmpty ? null : active.first;
  }

  ModelTestAttempt? _bestAttemptFor(String testId) {
    final attempts = _attemptsFor(testId)
      ..sort((a, b) {
        final byScore = b.percentage.compareTo(a.percentage);
        if (byScore != 0) return byScore;
        return (b.submittedAt ?? b.startedAt ?? DateTime.now()).compareTo(
          a.submittedAt ?? a.startedAt ?? DateTime.now(),
        );
      });
    return attempts.isEmpty ? null : attempts.first;
  }

  void _syncSelectedSubject(StudentModelTestProgress progress) {
    final names = progress.subjects
        .map((item) => item.subjectName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty) {
      _selectedSubject = null;
      return;
    }
    if (_selectedSubject == null || !names.contains(_selectedSubject)) {
      _selectedSubject = names.first;
    }
  }

  /// Local fallback when the aggregate RPC is unavailable. Still restricted to
  /// submitted official attempts; practice rounds are never in `_attempts`.
  StudentModelTestProgress _fallbackProgress(
    List<ModelTestAttempt> attempts,
    List<ModelTest> tests,
  ) {
    final submitted = attempts.where((item) => item.isSubmitted).toList();
    if (submitted.isEmpty) return StudentModelTestProgress.empty();

    // Every value is clamped before it can reach a Text or progress indicator.
    double safeSum(Iterable<double> values) => values.fold<double>(
      0,
      (total, value) => total + _safeMetric(value, max: 1000000),
    );
    int sumInt(Iterable<int> values) =>
        values.fold<int>(0, (total, value) => total + (value < 0 ? 0 : value));
    String subjectNameFor(ModelTestAttempt attempt) {
      final test = tests.where((item) => item.id == attempt.testId);
      final name = test.isEmpty ? '' : test.first.subjectName.trim();
      return name.isEmpty ? 'অনির্দিষ্ট' : name;
    }

    final passed = submitted.where((item) => item.passed).length;
    final overall = StudentOverallProgress(
      testsTaken: submitted.length,
      totalScore: safeSum(submitted.map((item) => item.score)),
      maxScore: safeSum(submitted.map((item) => item.totalMarks)),
      averageScore: _safeMetric(
        safeSum(submitted.map((item) => item.score)) / submitted.length,
      ),
      averagePercentage: _safePercent(
        safeSum(submitted.map((item) => item.percentage)) / submitted.length,
      ),
      passRate: _safePercent(passed * 100 / submitted.length),
      correct: sumInt(submitted.map((item) => item.correctCount)),
      wrong: sumInt(submitted.map((item) => item.wrongCount)),
      unanswered: sumInt(submitted.map((item) => item.unansweredCount)),
    );

    final subjectNames = <String>{
      for (final attempt in submitted) subjectNameFor(attempt),
    };
    final subjects = subjectNames.map((name) {
      final rows =
          submitted.where((attempt) => subjectNameFor(attempt) == name).toList()
            ..sort((a, b) {
              final timeA = a.submittedAt ?? a.startedAt ?? DateTime(0);
              final timeB = b.submittedAt ?? b.startedAt ?? DateTime(0);
              return timeB.compareTo(timeA);
            });
      final best = rows.reduce(
        (a, b) =>
            _safePercent(b.percentage) >= _safePercent(a.percentage) ? b : a,
      );
      final latest = rows.first;
      final passCount = rows.where((item) => item.passed).length;
      return SubjectTestProgress(
        subjectName: name,
        testsTaken: rows.length,
        totalScore: safeSum(rows.map((item) => item.score)),
        maxScore: safeSum(rows.map((item) => item.totalMarks)),
        averageScore: _safeMetric(
          safeSum(rows.map((item) => item.score)) / rows.length,
        ),
        averagePercentage: _safePercent(
          safeSum(rows.map((item) => item.percentage)) / rows.length,
        ),
        passRate: _safePercent(passCount * 100 / rows.length),
        correct: sumInt(rows.map((item) => item.correctCount)),
        wrong: sumInt(rows.map((item) => item.wrongCount)),
        unanswered: sumInt(rows.map((item) => item.unansweredCount)),
        bestScore: _safeMetric(best.score),
        bestTotal: _safeMetric(best.totalMarks),
        bestPercentage: _safePercent(best.percentage),
        latestScore: _safeMetric(latest.score),
        latestTotal: _safeMetric(latest.totalMarks),
        latestPercentage: _safePercent(latest.percentage),
      );
    }).toList()..sort((a, b) => a.subjectName.compareTo(b.subjectName));

    final history =
        submitted.map((attempt) {
          final test = tests.where((item) => item.id == attempt.testId);
          final title = test.isEmpty ? '' : test.first.examTitle.trim();
          return RecentTestProgress(
            testId: attempt.testId,
            title: title.isEmpty ? 'পরীক্ষা' : title,
            subjectName: subjectNameFor(attempt) == 'অনির্দিষ্ট'
                ? ''
                : subjectNameFor(attempt),
            submittedAt: attempt.submittedAt,
            score: _safeMetric(attempt.score),
            totalMarks: _safeMetric(attempt.totalMarks),
            percentage: _safePercent(attempt.percentage),
            passed: attempt.passed,
          );
        }).toList()..sort((a, b) {
          final timeA = a.submittedAt ?? DateTime(0);
          final timeB = b.submittedAt ?? DateTime(0);
          return timeB.compareTo(timeA);
        });

    return StudentModelTestProgress(
      studentId: widget.studentId.trim(),
      className: widget.className.trim(),
      overall: overall,
      subjects: subjects.take(30).toList(),
      history: history.take(10).toList(),
    );
  }

  /// A test is out of its official window once the teacher marked it expired
  /// or the scheduled end time has passed. Such tests stay visible for
  /// practice, but the official RPC must never be called for them.
  bool _isTimeOver(ModelTest test, [DateTime? now]) {
    final moment = now ?? DateTime.now();
    return test.isExpired ||
        (test.endAt != null && !moment.isBefore(test.endAt!));
  }

  Future<void> _openPractice(ModelTest test) async {
    if (test.questions.isEmpty) {
      Get.snackbar(
        'তথ্য',
        'এই পরীক্ষার প্রশ্নগুলো পাওয়া যায়নি, তাই অনুশীলন করা যাচ্ছে না।',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    await Get.to(() => ModelTestPracticeView(test: test));
  }

  Future<void> _openTest(ModelTest test) async {
    if (test.isDraft || test.isCancelled) {
      Get.snackbar(
        'তথ্য',
        test.isDraft
            ? 'এই পরীক্ষাটি এখনো প্রকাশিত হয়নি।'
            : 'এই পরীক্ষাটি বাতিল করা হয়েছে।',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    if (_isTimeOver(test)) {
      // Never call start_model_test_attempt for a closed window: the backend
      // rejects it, and a practice round must not create an official attempt.
      await _openPractice(test);
      return;
    }
    if (!test.isPublished) {
      Get.snackbar(
        'তথ্য',
        'এই পরীক্ষাটি এখন উপলব্ধ নয়।',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    if (test.startAt != null && DateTime.now().isBefore(test.startAt!)) {
      Get.snackbar(
        'অপেক্ষা করুন',
        'পরীক্ষা ${formatLocal(test.startAt)} হতে শুরু হবে।',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    // A live attempt is not a fresh start: resume it immediately, bypassing
    // ModelTestStartConfirmation entirely. Only fresh starts and practice ask.
    final active = _activeAttemptFor(test.id);
    final shouldResume = active != null && !_isTimeOver(test) && test.isRunning;
    await Get.to(
      () => ModelTestTakingView(
        test: test,
        studentId: widget.studentId,
        skipConfirmation: shouldResume,
      ),
    );
    unawaited(_load());
  }

  /// Pushes the route synchronously with cached data. No RPC is awaited here:
  /// the details screen refreshes in the background after its first frame.
  void _openProgressDetails() {
    if (!mounted) return;
    final academyId = widget.academyId.trim();
    final className = widget.className.trim();
    if (academyId.isEmpty) {
      Get.snackbar(
        'তথ্য',
        'প্রতিষ্ঠানের তথ্য পাওয়া যায়নি। অনুগ্রহ করে আবার লগইন করুন।',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    // Pass an immutable snapshot; the details screen re-fetches async anyway.
    final snapshot = StudentModelTestProgress(
      studentId: widget.studentId.trim(),
      className: className,
      overall: _progress.overall,
      subjects: List<SubjectTestProgress>.from(_progress.subjects),
      history: List<RecentTestProgress>.from(_progress.history),
    );
    try {
      final Future<void>? route = Get.to<void>(
        () => StudentProgressDetailsView(
          academyId: academyId,
          className: className,
          initialProgress: snapshot,
          onProgressChanged: (progress) {
            if (!mounted) return;
            try {
              setState(() {
                _progress = progress;
                _syncSelectedSubject(progress);
              });
            } catch (_) {
              // A late refresh must never tear down the parent screen.
            }
          },
        ),
      );
      unawaited(
        route?.catchError((Object error, StackTrace _) {
          _showProgressError(error);
        }),
      );
    } catch (e) {
      _showProgressError(e);
    }
  }

  Future<void> _openResult(ModelTest test) async {
    final attempt = _bestAttemptFor(test.id);
    if (attempt == null || !attempt.isSubmitted) {
      Get.snackbar(
        'তথ্য',
        'এই পরীক্ষায় আপনার কোনো জমা দেওয়া উত্তর নেই।',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    await Get.to(
      () => ModelTestResultView(
        attemptId: attempt.id,
        academyId: widget.academyId,
        studentId: widget.studentId,
        test: test,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = _tests.where((test) => !test.isFinished).toList();
    final previous = _tests.where((test) => test.isFinished).toList()
      ..sort((a, b) {
        final aEnd = a.endAt ?? DateTime(0);
        final bEnd = b.endAt ?? DateTime(0);
        return bEnd.compareTo(aEnd);
      });

    return Scaffold(
      backgroundColor: AppTheme.altSurfaceOf(context),
      appBar: AppBar(
        title: const Text('মডেল টেস্ট ও পরীক্ষা'),
        backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'রিফ্রেশ',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'রিমাইন্ডার',
            onPressed: _showReminderSheet,
            icon: Badge(
              isLabelVisible: _reminders.isNotEmpty,
              label: Text('${_reminders.length}'),
              backgroundColor: Colors.amber,
              child: Icon(
                _reminders.isEmpty
                    ? Icons.notifications_none_rounded
                    : Icons.notifications_active_rounded,
                color: _reminders.isEmpty ? null : Colors.amberAccent,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _tests.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 54,
                        color: AppTheme.errorOf(context),
                      ),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('আবার চেষ্টা করুন'),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => _load(),
                child: ListView(
                  // Extra bottom room keeps the final card clear of the
                  // bottom banner/ad controls.
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 88),
                  children: [
                    _buildStats(),
                    const SizedBox(height: 20),
                    _buildHeader('চলতি ও আসন্ন পরীক্ষা', running.length),
                    const SizedBox(height: 10),
                    if (running.isEmpty)
                      _buildEmpty('এই মুহূর্তে কোনো চলতি পরীক্ষা নেই।')
                    else
                      ...running.map(
                        (test) => _buildTestCard(test, isActive: true),
                      ),
                    const SizedBox(height: 20),
                    _buildHeader('পূর্ববর্তী পরীক্ষা ও ফলাফল', previous.length),
                    const SizedBox(height: 10),
                    if (previous.isEmpty)
                      _buildEmpty('কোনো পূর্ববর্তী পরীক্ষার রেকর্ড নেই।')
                    else
                      ...previous.map(
                        (test) => _buildTestCard(test, isActive: false),
                      ),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: _isBannerAdLoaded && _bannerAd != null
          ? SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildHeader(String title, int count) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.inkOf(context),
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.tileOf(context, Colors.indigo),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppTheme.tileInkOf(context, Colors.indigo),
          ),
        ),
      ),
    ],
  );

  Widget _buildEmpty(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.surfaceOf(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.borderOf(context)),
    ),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13, color: AppTheme.mutedOf(context)),
    ),
  );

  /// Real statistics derived from submitted official attempts only.
  Widget _buildStats() {
    final overall = _progress.overall;
    SubjectTestProgress? selectedSubject;
    for (final subject in _progress.subjects) {
      if (subject.subjectName == _selectedSubject) {
        selectedSubject = subject;
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.tileOf(context, Colors.indigo),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.tileOf(context, Colors.indigo)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights,
                size: 18,
                color: AppTheme.tileInkOf(context, Colors.indigo),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'আপনার অগ্রগতি',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.tileInkOf(context, Colors.indigo),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _handleProgressDetailsTap,
                icon: const Icon(Icons.analytics_outlined, size: 16),
                label: const Text('ডিটেইলস'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.tileInkOf(context, Colors.indigo),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 30),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStat('সম্পন্ন পরীক্ষা', bn(overall.testsTaken)),
              ),
              Expanded(
                child: _buildStat(
                  'গড় ফলাফল',
                  '${bnNum(_safePercent(overall.averagePercentage))}%',
                ),
              ),
              Expanded(
                child: _buildStat(
                  'সঠিক / ভুল',
                  '${bn(overall.correct)}/${bn(overall.wrong)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _handleProgressDetailsTap,
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'পাস রেট',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.tileInkOf(context, Colors.indigo),
                          ),
                        ),
                      ),
                      Text(
                        '${bnNum(_safePercent(overall.passRate))}%',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.tileInkOf(context, Colors.indigo),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progressFraction(overall.passRate),
                      minHeight: 7,
                      backgroundColor: AppTheme.borderOf(context),
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${bn(overall.testsTaken)} টি জমা দেওয়া অফিশিয়াল পরীক্ষা • বিবরণ দেখতে ট্যাপ করুন',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.tileInkOf(
                        context,
                        Colors.indigo,
                      ).withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_progress.subjects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 14,
                    color: AppTheme.tileInkOf(context, Colors.indigo),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _selectedSubject,
                      isExpanded: true,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: AppTheme.surfaceOf(context),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.tileInkOf(context, Colors.indigo),
                      ),
                      items: _progress.subjects
                          .map(
                            (subject) => DropdownMenuItem<String>(
                              value: subject.subjectName,
                              child: Text(
                                subject.subjectName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedSubject = value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.tileOf(context, Colors.teal),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              selectedSubject == null
                  ? 'শ্রেণিতে অবস্থান: এখনো ফলাফল নেই'
                  : 'শ্রেণিতে অবস্থান (${selectedSubject.subjectName}): '
                        '${_rankLabel(selectedSubject.rank, selectedSubject.totalStudents)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.tileInkOf(context, Colors.teal),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: AppTheme.tileInkOf(context, Colors.indigo),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: AppTheme.tileInkOf(
            context,
            Colors.indigo,
          ).withValues(alpha: 0.75),
        ),
      ),
    ],
  );

  Widget _buildTestCard(ModelTest test, {required bool isActive}) {
    final attempts = _attemptsFor(test.id);
    final active = _activeAttemptFor(test.id);
    final best = _bestAttemptFor(test.id);
    final hasReminder = _reminders.any((item) => item.testId == test.id);

    Widget buildCard(DateTime now) {
      final timeOver = _isTimeOver(test, now);
      final beforeStart = test.startAt != null && now.isBefore(test.startAt!);
      final runningNow =
          test.startAt != null &&
          test.endAt != null &&
          !now.isBefore(test.startAt!) &&
          now.isBefore(test.endAt!);
      final canStart = test.isPublished && !timeOver && runningNow;
      final canRejoin = active != null && canStart;
      final badgeColor = timeOver
          ? Colors.orange
          : beforeStart
          ? Colors.indigo
          : runningNow
          ? Colors.green
          : Colors.grey;
      final statusText = timeOver
          ? 'মেয়াদ শেষ • অনুশীলন'
          : beforeStart
          ? 'আসন্ন'
          : runningNow
          ? 'চলছে'
          : test.statusLabel;

      return Card(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Finite width for every metadata item so a long chapter/date can
            // ellipsise instead of forcing the card wider than the screen.
            final metaWidth = constraints.maxWidth > 80
                ? constraints.maxWidth - 46
                : 160.0;
            return Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.quiz_rounded,
                        size: 20,
                        color: timeOver
                            ? Colors.orange
                            : isActive
                            ? Colors.indigo
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          test.examTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.inkOf(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.tileOf(context, badgeColor),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.tileInkOf(context, badgeColor),
                            ),
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
                      _buildMeta(
                        Icons.book_outlined,
                        test.subjectName,
                        maxWidth: metaWidth,
                      ),
                      _buildMeta(
                        Icons.menu_book_outlined,
                        test.chapterName.isEmpty
                            ? 'সম্পুর্ণ বই'
                            : test.chapterName,
                        maxWidth: metaWidth,
                      ),
                      _buildMeta(
                        Icons.help_outline,
                        '${bn(test.questionCount)} প্রশ্ন',
                        maxWidth: metaWidth,
                      ),
                      _buildMeta(
                        Icons.star_border,
                        '${bn(_fmt(test.totalMarks))} নম্বর',
                        maxWidth: metaWidth,
                      ),
                      _buildMeta(
                        Icons.timer_outlined,
                        '${bn(test.durationMinutes)} মিনিট',
                        maxWidth: metaWidth,
                      ),
                    ],
                  ),
                  if (test.startAt != null) ...[
                    const SizedBox(height: 8),
                    _buildMeta(
                      Icons.schedule,
                      'শুরু: ${formatLocal(test.startAt)}',
                      maxWidth: metaWidth,
                    ),
                    const SizedBox(height: 5),
                    _buildMeta(
                      Icons.event_outlined,
                      'শেষ: ${formatLocal(test.endAt)}',
                      maxWidth: metaWidth,
                    ),
                  ],
                  if (isActive &&
                      !timeOver &&
                      test.startAt != null &&
                      test.endAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: _LiveCountdownBadge(
                        startAt: test.startAt!,
                        endAt: test.endAt!,
                        now: now,
                      ),
                    ),
                  if (timeOver) ...[
                    const SizedBox(height: 10),
                    _buildPracticeNotice(),
                  ],
                  if (best != null && best.isSubmitted) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.tileOf(
                          context,
                          best.passed ? Colors.green : Colors.red,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'সেরা ফলাফল: ${bn(_fmt(best.score))}/${bn(_fmt(best.totalMarks))} • ${bnNum(best.percentage)}% • ${bn(attempts.length)} প্রচেষ্টা',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.tileInkOf(
                            context,
                            best.passed ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (isActive &&
                            !timeOver &&
                            test.startAt != null &&
                            test.endAt != null)
                          IconButton(
                            tooltip: hasReminder
                                ? 'রিমাইন্ডার বাতিল করুন'
                                : '৩০ মিনিট আগে রিমাইন্ডার',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 34,
                              height: 34,
                            ),
                            onPressed: () => _toggleQuickReminder(test),
                            icon: Icon(
                              hasReminder
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_none_rounded,
                              color: hasReminder
                                  ? Colors.amber
                                  : AppTheme.mutedOf(context),
                              size: 20,
                            ),
                          ),
                        if (best != null && best.isSubmitted)
                          _cardButton(
                            icon: Icons.assignment_outlined,
                            label: 'ফলাফল',
                            color: Colors.indigo,
                            onPressed: () => _openResult(test),
                          ),
                        if (timeOver)
                          _cardButton(
                            icon: Icons.school_outlined,
                            label: 'অনুশীলন পরীক্ষা দিন',
                            color: Colors.orange,
                            filled: true,
                            onPressed: () => _openPractice(test),
                          )
                        else if (isActive)
                          _cardButton(
                            icon: canRejoin
                                ? Icons.play_arrow
                                : Icons.assignment_add,
                            label: canRejoin
                                ? 'আবার যোগ দিন'
                                : beforeStart
                                ? 'আসন্ন'
                                : 'পরীক্ষা শুরু করুন',
                            color: Colors.teal,
                            filled: true,
                            enabled: canStart,
                            onPressed: () => _openTest(test),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    // Active cards own a 1-second ticker so the countdown AND the start/rejoin
    // button state stay live even when the parent list is not rebuilding.
    if (isActive && test.startAt != null) {
      return _SecondTicker(builder: buildCard);
    }
    return buildCard(DateTime.now());
  }

  Widget _buildPracticeNotice() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.tileOf(context, Colors.orange),
      borderRadius: BorderRadius.circular(8),
    ),
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
            'সময় শেষ • অনুশীলন মোড। এখন দেওয়া উত্তর শুধু অনুশীলনের জন্য — ফলাফলে যুক্ত হবে না।',
            maxLines: 2,
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

  Widget _cardButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool filled = false,
    bool enabled = true,
  }) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    if (filled) {
      return ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 15),
        label: text,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(0, 34),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: shape,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 15),
      label: text,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 34),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: shape,
      ),
    );
  }

  Widget _buildMeta(IconData icon, String text, {double? maxWidth}) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.mutedOf(context)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppTheme.mutedOf(context)),
          ),
        ),
      ],
    );
    if (maxWidth == null) return row;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: row,
    );
  }

  /// Guards every progress handler: no navigation after dispose, no crash if
  /// widget arguments or cached progress data are missing/malformed.
  void _handleProgressDetailsTap() {
    if (!mounted) return;
    try {
      // Synchronous route push: the tap returns before any network work.
      _openProgressDetails();
    } catch (e) {
      _showProgressError(e);
    }
  }

  void _showProgressError(Object error) {
    if (!mounted) return;
    final message =
        'বিবরণ খোলা যায়নি। ${ModelTestRepository.friendlyError(error)}';
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Get.snackbar(
      'তথ্য',
      message,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );
  }

  double _safeMetric(double value, {double max = double.infinity}) {
    if (!value.isFinite) return 0;
    final bounded = value < 0 ? 0.0 : value;
    return max.isFinite && bounded > max ? max : bounded;
  }

  double _safePercent(double value) => _safeMetric(value, max: 100);

  double _progressFraction(double value) =>
      (_safePercent(value) / 100).clamp(0.0, 1.0).toDouble();

  String _rankLabel(int? rank, int totalStudents) {
    if (rank == null || rank < 1) return 'এখনো ফলাফল নেই';
    final total = totalStudents > 0 ? ' / ${bn(totalStudents)} জন' : '';
    return '${bnOrdinal(rank)}$total';
  }

  String _fmt(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

/// Rebuilds an active card once per second against the wall clock.
class _SecondTicker extends StatefulWidget {
  final Widget Function(DateTime now) builder;

  const _SecondTicker({required this.builder});

  @override
  State<_SecondTicker> createState() => _SecondTickerState();
}

class _SecondTickerState extends State<_SecondTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(DateTime.now());
}

/// Live upcoming/running badge. Both states use Bengali digits and a single
/// line so a long countdown ellipsises instead of overflowing the card.
class _LiveCountdownBadge extends StatelessWidget {
  final DateTime startAt;
  final DateTime endAt;
  final DateTime now;

  const _LiveCountdownBadge({
    required this.startAt,
    required this.endAt,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final beforeStart = now.isBefore(startAt);
    final left = beforeStart ? startAt.difference(now) : endAt.difference(now);
    if (left <= Duration.zero) return const SizedBox.shrink();

    final color = beforeStart
        ? Colors.teal
        : left.inMinutes < 5
        ? Colors.red
        : Colors.green;
    final label = beforeStart
        ? 'শুরু হতে বাকি: ${_formatCountdown(left)}'
        : 'চলছে (বাকি: ${_formatCountdown(left)})';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.tileOf(context, color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            beforeStart ? Icons.hourglass_bottom : Icons.timer,
            size: 15,
            color: AppTheme.tileInkOf(context, color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.tileInkOf(context, color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCountdown(Duration value) {
  final total = value.isNegative ? 0 : value.inSeconds;
  final days = total ~/ 86400;
  final hours = (total ~/ 3600) % 24;
  final minutes = (total ~/ 60) % 60;
  final seconds = total % 60;
  final clock =
      '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  return days > 0 ? '${bn(days)} দিন ${bn(clock)}' : bn(clock);
}

String formatLocal(DateTime? time) {
  if (time == null) return '-';
  final local = time.toLocal();
  return bn(DateFormat('dd MMM, yyyy - hh:mm a').format(local));
}
