/// Aggregate-only progress payload returned by `student_model_test_progress`.
///
/// The backend computes ranks from submitted official attempts inside the
/// current academy/class. No other student's personal details are exposed.
/// Every numeric field is sanitised here so malformed backend data can never
/// produce NaN/Infinity or crash a progress bar.
library;

import 'model_test.dart';

double _finiteDouble(
  dynamic value, {
  double fallback = 0,
  double min = 0,
  double? max,
}) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  if (parsed == null || !parsed.isFinite) return fallback;
  var result = parsed < min ? min : parsed;
  if (max != null && result > max) result = max;
  return result;
}

int _count(dynamic value) {
  final bounded = _finiteDouble(value, fallback: 0, min: 0, max: 1000000);
  return bounded.round();
}

int? _rank(dynamic value) {
  if (value == null) return null;
  final parsed = _finiteDouble(value, fallback: -1, min: -1, max: 1000000000);
  return parsed < 1 ? null : parsed.round();
}

String _text(dynamic value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

/// RPC payloads are untrusted: tolerate non-string keys and malformed rows
/// instead of letting `Map<String, dynamic>.from` throw a cast error.
Map<String, dynamic> _stringMap(dynamic value) {
  if (value is! Map) return <String, dynamic>{};
  return <String, dynamic>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

DateTime? _time(dynamic value) => localTime(value);

class StudentOverallProgress {
  final int? rank;
  final int totalStudents;
  final int testsTaken;
  final double totalScore;
  final double maxScore;
  final double averageScore;
  final double averagePercentage;
  final double passRate;
  final int correct;
  final int wrong;
  final int unanswered;

  const StudentOverallProgress({
    this.rank,
    this.totalStudents = 0,
    this.testsTaken = 0,
    this.totalScore = 0,
    this.maxScore = 0,
    this.averageScore = 0,
    this.averagePercentage = 0,
    this.passRate = 0,
    this.correct = 0,
    this.wrong = 0,
    this.unanswered = 0,
  });

  bool get hasResults => testsTaken > 0;

  factory StudentOverallProgress.fromMap(Map<String, dynamic> map) =>
      StudentOverallProgress(
        rank: _rank(map['rank']),
        totalStudents: _count(map['total_students']),
        testsTaken: _count(map['tests_taken']),
        totalScore: _finiteDouble(map['total_score']),
        maxScore: _finiteDouble(map['max_score']),
        averageScore: _finiteDouble(map['average_score']),
        averagePercentage: _finiteDouble(map['average_percentage'], max: 100),
        passRate: _finiteDouble(map['pass_rate'], max: 100),
        correct: _count(map['correct']),
        wrong: _count(map['wrong']),
        unanswered: _count(map['unanswered']),
      );
}

class SubjectTestProgress {
  final String subjectName;
  final int? rank;
  final int totalStudents;
  final int testsTaken;
  final double totalScore;
  final double maxScore;
  final double averageScore;
  final double averagePercentage;
  final double passRate;
  final int correct;
  final int wrong;
  final int unanswered;
  final double bestScore;
  final double bestTotal;
  final double bestPercentage;
  final double latestScore;
  final double latestTotal;
  final double latestPercentage;

  const SubjectTestProgress({
    required this.subjectName,
    this.rank,
    this.totalStudents = 0,
    this.testsTaken = 0,
    this.totalScore = 0,
    this.maxScore = 0,
    this.averageScore = 0,
    this.averagePercentage = 0,
    this.passRate = 0,
    this.correct = 0,
    this.wrong = 0,
    this.unanswered = 0,
    this.bestScore = 0,
    this.bestTotal = 0,
    this.bestPercentage = 0,
    this.latestScore = 0,
    this.latestTotal = 0,
    this.latestPercentage = 0,
  });

  factory SubjectTestProgress.fromMap(Map<String, dynamic> map) =>
      SubjectTestProgress(
        subjectName: _text(map['subject_name'], 'অনির্দিষ্ট'),
        rank: _rank(map['rank']),
        totalStudents: _count(map['total_students']),
        testsTaken: _count(map['tests_taken']),
        totalScore: _finiteDouble(map['total_score']),
        maxScore: _finiteDouble(map['max_score']),
        averageScore: _finiteDouble(map['average_score']),
        averagePercentage: _finiteDouble(map['average_percentage'], max: 100),
        passRate: _finiteDouble(map['pass_rate'], max: 100),
        correct: _count(map['correct']),
        wrong: _count(map['wrong']),
        unanswered: _count(map['unanswered']),
        bestScore: _finiteDouble(map['best_score']),
        bestTotal: _finiteDouble(map['best_total']),
        bestPercentage: _finiteDouble(map['best_percentage'], max: 100),
        latestScore: _finiteDouble(map['latest_score']),
        latestTotal: _finiteDouble(map['latest_total']),
        latestPercentage: _finiteDouble(map['latest_percentage'], max: 100),
      );
}

class RecentTestProgress {
  final String testId;
  final String title;
  final String subjectName;
  final DateTime? submittedAt;
  final double score;
  final double totalMarks;
  final double percentage;
  final bool passed;

  const RecentTestProgress({
    this.testId = '',
    this.title = '',
    this.subjectName = '',
    this.submittedAt,
    this.score = 0,
    this.totalMarks = 0,
    this.percentage = 0,
    this.passed = false,
  });

  factory RecentTestProgress.fromMap(Map<String, dynamic> map) =>
      RecentTestProgress(
        testId: _text(map['test_id']),
        title: _text(map['title'], 'পরীক্ষা'),
        subjectName: _text(map['subject_name']),
        submittedAt: _time(map['submitted_at']),
        score: _finiteDouble(map['score']),
        totalMarks: _finiteDouble(map['total_marks']),
        percentage: _finiteDouble(map['percentage'], max: 100),
        passed: map['passed'] == true,
      );
}

class StudentModelTestProgress {
  final String studentId;
  final String className;
  final StudentOverallProgress overall;
  final List<SubjectTestProgress> subjects;
  final List<RecentTestProgress> history;

  const StudentModelTestProgress({
    this.studentId = '',
    this.className = '',
    this.overall = const StudentOverallProgress(),
    this.subjects = const <SubjectTestProgress>[],
    this.history = const <RecentTestProgress>[],
  });

  bool get hasResults =>
      overall.hasResults || subjects.isNotEmpty || history.isNotEmpty;

  factory StudentModelTestProgress.empty() => const StudentModelTestProgress();

  /// Never throws on null, non-map, or partially malformed RPC responses.
  factory StudentModelTestProgress.fromObject(Object? value) {
    if (value is StudentModelTestProgress) return value;
    final map = _stringMap(value);
    final rawSubjects = map['subjects'];
    final rawHistory = map['history'];
    return StudentModelTestProgress(
      studentId: _text(map['student_id']),
      className: _text(map['class_name']),
      overall: StudentOverallProgress.fromMap(_stringMap(map['overall'])),
      subjects: rawSubjects is List
          ? rawSubjects
                .whereType<Map>()
                .map((row) => SubjectTestProgress.fromMap(_stringMap(row)))
                .take(50)
                .toList()
          : const <SubjectTestProgress>[],
      history: rawHistory is List
          ? rawHistory
                .whereType<Map>()
                .map((row) => RecentTestProgress.fromMap(_stringMap(row)))
                .take(50)
                .toList()
          : const <RecentTestProgress>[],
    );
  }

  factory StudentModelTestProgress.fromMap(Map<String, dynamic> map) =>
      StudentModelTestProgress.fromObject(map);
}
