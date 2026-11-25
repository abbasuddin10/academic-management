import 'package:academy_management/config/app_theme.dart';
import 'package:academy_management/models/model_test.dart';
import 'package:academy_management/repositories/model_test_repository.dart';
import 'package:academy_management/views/exams/model_test_result_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Staff view of every attempt for one model test.
class ModelTestResultsView extends StatefulWidget {
  final ModelTest test;

  const ModelTestResultsView({super.key, required this.test});

  @override
  State<ModelTestResultsView> createState() => _ModelTestResultsViewState();
}

class _ModelTestResultsViewState extends State<ModelTestResultsView> {
  final _repository = ModelTestRepository();

  bool _isLoading = true;
  String? _error;
  List<ModelTestAttempt> _attempts = <ModelTestAttempt>[];

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
      final attempts = await _repository.fetchAttempts(
        academyId: widget.test.academyId,
        testId: widget.test.id,
      );
      if (!mounted) return;
      setState(() {
        _attempts = attempts;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.altSurfaceOf(context),
      appBar: AppBar(
        title: Text(
          widget.test.examTitle,
          style: const TextStyle(fontSize: 15),
        ),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
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
              child: _attempts.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            'এখনো কোনো শিক্ষার্থী এই পরীক্ষায় অংশগ্রহণ করেনি।',
                            style: TextStyle(color: AppTheme.mutedOf(context)),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: _attempts.length,
                      itemBuilder: (context, index) {
                        final attempt = _attempts[index];
                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.tileOf(
                                context,
                                attempt.passed ? Colors.teal : Colors.red,
                              ),
                              child: Text(
                                '${attempt.correctCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.tileInkOf(
                                    context,
                                    attempt.passed ? Colors.teal : Colors.red,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              'রোল: ${attempt.studentRoll.isEmpty ? "-" : attempt.studentRoll}  •  ${attempt.statusLabel}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${attempt.score.toStringAsFixed(1)} / ${attempt.totalMarks.toStringAsFixed(1)} • ${attempt.percentage.toStringAsFixed(1)}% • সঠিক ${attempt.correctCount}, ভুল ${attempt.wrongCount}',
                              style: TextStyle(fontSize: 11),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Get.to(
                              () => ModelTestResultView(
                                attemptId: attempt.id,
                                academyId: widget.test.academyId,
                                studentId: attempt.studentId,
                                test: widget.test,
                                readOnly: true,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
