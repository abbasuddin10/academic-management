import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/models/model_test.dart';
import 'package:academy_management/repositories/model_test_repository.dart';
import 'package:academy_management/services/result_calculator.dart';
import 'package:academy_management/views/exams/model_test_taking_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Real result breakdown for one model-test attempt. Read-only for
/// admin/teacher (RLS allows staff to read every attempt in their academy).
class ModelTestResultView extends StatefulWidget {
  final String attemptId;
  final String academyId;
  final String? studentId;
  final ModelTest? test;
  final bool readOnly;

  const ModelTestResultView({
    super.key,
    required this.attemptId,
    required this.academyId,
    this.studentId,
    this.test,
    this.readOnly = false,
  });

  @override
  State<ModelTestResultView> createState() => _ModelTestResultViewState();
}

class _ModelTestResultViewState extends State<ModelTestResultView> {
  final _repository = ModelTestRepository();

  bool _isLoading = true;
  String? _error;
  ModelTestAttempt? _attempt;
  ModelTest? _test;
  List<ModelTestAnswer> _answers = <ModelTestAnswer>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final attempt = await _repository.fetchAttempt(widget.attemptId);
      if (attempt == null) throw const FormatException('ফলাফল পাওয়া যায়নি।');
      final test = widget.test ?? await _repository.fetchTest(attempt.testId);
      final answers = await _repository.fetchAnswers(widget.attemptId);
      if (!mounted) return;
      setState(() {
        _attempt = attempt;
        _test = test;
        _answers = answers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ModelTestRepository.friendlyError(e);
        _isLoading = false;
      });
    }
  }

  Map<String, ModelTestAnswer> get _answerByQuestion => {
    for (final answer in _answers) answer.questionId: answer,
  };

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('মডেল টেস্টের ফলাফল')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _attempt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('মডেল টেস্টের ফলাফল')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 52,
                  color: AppTheme.errorOf(context),
                ),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'ফলাফল পাওয়া যায়নি।',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _load,
                  child: const Text('আবার চেষ্টা করুন'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final attempt = _attempt!;
    final test = _test;
    final byQuestion = _answerByQuestion;
    final grade = ResultCalculator.gradeFor(attempt.percentage);

    return Scaffold(
      backgroundColor: AppTheme.altSurfaceOf(context),
      appBar: AppBar(
        title: const Text('মডেল টেস্টের ফলাফল'),
        backgroundColor: AppTheme.tileInkOf(context, Colors.indigo),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'রিফ্রেশ',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            _buildSummary(attempt, grade.label, grade.remark),
            const SizedBox(height: 16),
            Text(
              'প্রশ্ন অনুযায়ী ফলাফল',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.inkOf(context),
              ),
            ),
            const SizedBox(height: 8),
            if (test == null || test.questions.isEmpty)
              _buildInfoCard('এই পরীক্ষার প্রশ্নের বিবরণ উপলব্ধ নেই।')
            else
              ...List.generate(test.questions.length, (index) {
                final question = test.questions[index];
                final answer = byQuestion[question.id];
                return _buildQuestionTile(index, question, answer);
              }),
          ],
        ),
      ),
      bottomNavigationBar: _buildActions(attempt, test),
    );
  }

  Widget _buildSummary(ModelTestAttempt attempt, String grade, String remark) {
    final color = attempt.passed ? Colors.teal : Colors.red;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.tileOf(context, color),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.tileOf(context, color)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _test?.examTitle ?? 'মডেল টেস্ট',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.tileInkOf(context, color),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStat(
                  'প্রাপ্ত নম্বর',
                  '${_fmt(attempt.score)} / ${_fmt(attempt.totalMarks)}',
                  color,
                ),
              ),
              Expanded(
                child: _buildStat(
                  'শতাংশ',
                  '${attempt.percentage.toStringAsFixed(1)}%',
                  color,
                ),
              ),
              Expanded(child: _buildStat('গ্রেড', grade, color)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            attempt.passed ? 'উত্তীর্ণ — $remark' : 'অনুত্তীর্ণ — $remark',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.tileInkOf(context, color),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCount('সঠিক', attempt.correctCount, Colors.green),
              _buildCount('ভুল', attempt.wrongCount, Colors.red),
              _buildCount('উত্তরহীন', attempt.unansweredCount, Colors.grey),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${attempt.statusLabel} • ${attempt.submittedAt != null ? _formatTime(attempt.submittedAt!) : '-'}',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.tileInkOf(context, color).withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: AppTheme.tileInkOf(context, color).withValues(alpha: 0.75),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppTheme.tileInkOf(context, color),
        ),
      ),
    ],
  );

  Widget _buildCount(String label, int count, Color color) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: AppTheme.mutedOf(context)),
          ),
        ],
      ),
    ),
  );

  Widget _buildQuestionTile(
    int index,
    ModelTestQuestion question,
    ModelTestAnswer? answer,
  ) {
    final selected = answer?.selectedOption;
    final isCorrect = answer?.isCorrect ?? false;
    final color = isCorrect ? Colors.green : Colors.red;
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: AppTheme.tileOf(context, color),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.tileInkOf(context, color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    question.question,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkOf(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildAnswerRow(
              'আপনার উত্তর',
              selected == null || selected.isEmpty
                  ? 'উত্তর দেননি'
                  : '$selected. ${question.optionText(selected)}',
              color,
            ),
            const SizedBox(height: 5),
            _buildAnswerRow(
              'সঠিক উত্তর',
              '${question.correctOption}. ${question.optionText(question.correctOption)}',
              Colors.green,
            ),
            const SizedBox(height: 5),
            _buildAnswerRow(
              'প্রাপ্ত নম্বর',
              _fmt(answer?.marksAwarded ?? 0),
              isCorrect ? Colors.green : Colors.red,
            ),
            if ((question.explanation).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'ব্যাখ্যা: ${question.explanation}',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.mutedOf(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerRow(String label, String value, Color color) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 95,
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: AppTheme.mutedOf(context)),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    ],
  );

  Widget _buildInfoCard(String message) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.surfaceOf(context),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message, style: TextStyle(color: AppTheme.mutedOf(context))),
  );

  Widget? _buildActions(ModelTestAttempt attempt, ModelTest? test) {
    final canRetry =
        !widget.readOnly &&
        test != null &&
        test.isRunning &&
        (widget.studentId == null || widget.studentId!.isNotEmpty);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        border: Border(top: BorderSide(color: AppTheme.borderOf(context))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Get.back(),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('ফিরে যান'),
            ),
          ),
          if (canRetry) ...[
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Get.off(
                  () => ModelTestTakingView(
                    test: test,
                    studentId: widget.studentId ?? '',
                  ),
                ),
                icon: const Icon(Icons.replay, size: 16),
                label: const Text('আবার চেষ্টা করুন'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  String _formatTime(DateTime time) =>
      '${time.day}/${time.month}/${time.year} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
