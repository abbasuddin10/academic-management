/// Data models for the complete model-test flow.
///
/// All timestamps are normalised to the device's local zone at the boundary:
/// Supabase stores UTC ISO strings, so callers must never re-interpret the
/// parsed UTC fields as local time (that caused an offset bug previously).
library;

import 'dart:convert';

DateTime? localTime(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

double asDouble(dynamic value, [double fallback = 0]) =>
    double.tryParse(value?.toString() ?? '') ?? fallback;

int asInt(dynamic value, [int fallback = 0]) =>
    int.tryParse(value?.toString() ?? '') ?? fallback;

Map<String, dynamic> asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

/// Always returns a valid JSON **array** string for `selected_question_ids`,
/// regardless of whether Supabase returned a jsonb list, a JSON text string,
/// a double-encoded string, or legacy/non-JSON data.
String normalizeJsonIdArray(dynamic value) {
  if (value == null) return '[]';
  if (value is List) {
    return jsonEncode(_cleanJsonIds(value));
  }
  final text = value.toString().trim();
  if (text.isEmpty) return '[]';
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return jsonEncode(_cleanJsonIds(decoded));
    }
  } catch (_) {
    // Legacy value was never JSON — treat it as an empty selection.
  }
  return '[]';
}

List<String> _cleanJsonIds(Iterable<dynamic> values) => values
    .map((item) => item.toString().trim())
    .where((id) => id.isNotEmpty && !_isPlaceholderJsonId(id))
    .toList();

bool _isPlaceholderJsonId(String id) {
  final value = id.toLowerCase();
  return value == '—' ||
      value == '–' ||
      value == '-' ||
      value == '|' ||
      value == 'n/a' ||
      value == 'na' ||
      value == 'null' ||
      RegExp(r'^[\s\-–—._/|]+$').hasMatch(id);
}

class ModelTestQuestion {
  final String id;
  final String question;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String correctOption;
  final String explanation;
  final String chapterName;

  const ModelTestQuestion({
    required this.id,
    required this.question,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.correctOption,
    this.explanation = '',
    this.chapterName = '',
  });

  factory ModelTestQuestion.fromMap(Map<String, dynamic> map) =>
      ModelTestQuestion(
        id: map['id']?.toString() ?? '',
        question: map['question']?.toString() ?? '',
        optionA: map['option_a']?.toString() ?? '',
        optionB: map['option_b']?.toString() ?? '',
        optionC: map['option_c']?.toString() ?? '',
        optionD: map['option_d']?.toString() ?? '',
        correctOption: (map['correct_option']?.toString() ?? '')
            .trim()
            .toUpperCase(),
        explanation: map['explanation']?.toString() ?? '',
        chapterName: map['chapter_name']?.toString() ?? '',
      );

  List<String> get options => [optionA, optionB, optionC, optionD];

  String optionText(String key) {
    switch (key.toUpperCase()) {
      case 'A':
        return optionA;
      case 'B':
        return optionB;
      case 'C':
        return optionC;
      case 'D':
        return optionD;
      default:
        return '';
    }
  }
}

class ModelTest {
  final String id;
  final String academyId;
  final String className;
  final String subjectName;
  final String examTitle;
  final String chapterName;
  final String status;
  final String creatorId;
  final String creatorName;
  final String selectedQuestionIds;
  final int questionCount;
  final int durationMinutes;
  final double totalMarks;
  final double marksPerQuestion;
  final double negativeMarks;
  final double passPercent;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool isActive;
  final List<ModelTestQuestion> questions;

  const ModelTest({
    required this.id,
    required this.academyId,
    required this.className,
    required this.subjectName,
    required this.examTitle,
    required this.chapterName,
    required this.status,
    required this.creatorId,
    required this.creatorName,
    required this.selectedQuestionIds,
    required this.questionCount,
    required this.durationMinutes,
    required this.totalMarks,
    required this.marksPerQuestion,
    required this.negativeMarks,
    required this.passPercent,
    required this.startAt,
    required this.endAt,
    required this.isActive,
    this.questions = const <ModelTestQuestion>[],
  });

  factory ModelTest.fromMap(Map<String, dynamic> map) {
    final snapshot = asMap(map['questions_snapshot']);
    final rawQuestions = snapshot['questions'];
    final questions = <ModelTestQuestion>[];
    if (rawQuestions is List) {
      for (final item in rawQuestions) {
        if (item is Map) {
          questions.add(
            ModelTestQuestion.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    } else if (map['questions_snapshot'] is List) {
      for (final item in (map['questions_snapshot'] as List)) {
        if (item is Map) {
          questions.add(
            ModelTestQuestion.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final selected = map['selected_question_ids'];
    return ModelTest(
      id: map['id']?.toString() ?? '',
      academyId: map['academy_id']?.toString() ?? '',
      className: map['class_name']?.toString() ?? '',
      subjectName: map['subject_name']?.toString() ?? '',
      examTitle: map['exam_title']?.toString() ?? '',
      chapterName: map['chapter_name']?.toString() ?? '',
      status: (map['status']?.toString() ?? 'published').trim().toLowerCase(),
      creatorId: map['question_creator_id']?.toString() ?? '',
      creatorName: map['question_creator_name']?.toString() ?? '',
      selectedQuestionIds: normalizeJsonIdArray(selected),
      questionCount: asInt(map['question_count']),
      durationMinutes: asInt(map['duration_minutes'], 30),
      totalMarks: asDouble(
        map['total_marks'],
        asInt(map['question_count'], 1) * 1.0,
      ),
      marksPerQuestion: asDouble(map['marks_per_question'], 1),
      negativeMarks: asDouble(map['negative_marks']),
      passPercent: asDouble(map['pass_percent'], 33),
      startAt: localTime(map['start_time']),
      endAt: localTime(map['end_time']),
      isActive: map['is_active'] == true,
      questions: questions,
    );
  }

  bool get isPublished => status == 'published';
  bool get isDraft => status == 'draft';
  bool get isCancelled => status == 'cancelled';
  bool get isExpired => status == 'expired';

  bool get isUpcoming =>
      isPublished && startAt != null && startAt!.isAfter(DateTime.now());

  bool get isRunning =>
      isPublished &&
      startAt != null &&
      endAt != null &&
      !DateTime.now().isBefore(startAt!) &&
      DateTime.now().isBefore(endAt!);

  bool get isFinished =>
      isExpired ||
      isCancelled ||
      (endAt != null && !DateTime.now().isBefore(endAt!));

  String get statusLabel {
    switch (status) {
      case 'draft':
        return 'খসরা';
      case 'cancelled':
        return 'বাতিল';
      case 'expired':
        return 'শেষ';
      default:
        return 'চলছে';
    }
  }

  Duration get windowDuration {
    if (startAt == null || endAt == null) return Duration.zero;
    final diff = endAt!.difference(startAt!);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Effective per-student duration: configured value, never beyond the
  /// scheduling window so a test cannot outlive its published slot.
  Duration get attemptDuration {
    final configured = Duration(
      minutes: durationMinutes > 0 ? durationMinutes : 30,
    );
    final window = windowDuration;
    if (window <= Duration.zero) return configured;
    return configured < window ? configured : window;
  }
}

class ModelTestAttempt {
  final String id;
  final String testId;
  final String academyId;
  final String studentId;
  final String studentRoll;
  final String className;
  final String status;
  final DateTime? startedAt;
  final DateTime? deadlineAt;
  final DateTime? submittedAt;
  final double score;
  final double totalMarks;
  final int correctCount;
  final int wrongCount;
  final int unansweredCount;
  final double percentage;
  final bool passed;

  const ModelTestAttempt({
    required this.id,
    required this.testId,
    required this.academyId,
    required this.studentId,
    required this.studentRoll,
    required this.className,
    required this.status,
    required this.startedAt,
    required this.deadlineAt,
    required this.submittedAt,
    required this.score,
    required this.totalMarks,
    required this.correctCount,
    required this.wrongCount,
    required this.unansweredCount,
    required this.percentage,
    required this.passed,
  });

  factory ModelTestAttempt.fromMap(Map<String, dynamic> map) =>
      ModelTestAttempt(
        id: map['id']?.toString() ?? '',
        testId: map['test_id']?.toString() ?? '',
        academyId: map['academy_id']?.toString() ?? '',
        studentId: map['student_id']?.toString() ?? '',
        studentRoll: map['student_roll']?.toString() ?? '',
        className: map['class_name']?.toString() ?? '',
        status: (map['status']?.toString() ?? 'in_progress').trim(),
        startedAt: localTime(map['started_at']),
        deadlineAt: localTime(map['deadline_at']),
        submittedAt: localTime(map['submitted_at']),
        score: asDouble(map['score']),
        totalMarks: asDouble(map['total_marks']),
        correctCount: asInt(map['correct_count']),
        wrongCount: asInt(map['wrong_count']),
        unansweredCount: asInt(map['unanswered_count']),
        percentage: asDouble(map['percentage']),
        passed: map['passed'] == true,
      );

  bool get isInProgress => status == 'in_progress';
  bool get isSubmitted => status == 'submitted' || status == 'auto_submitted';

  String get statusLabel {
    switch (status) {
      case 'in_progress':
        return 'চলছে';
      case 'auto_submitted':
        return 'সময় শেষে জমা';
      default:
        return 'জমা দেওয়া';
    }
  }
}

class ModelTestAnswer {
  final String questionId;
  final String? selectedOption;
  final bool isCorrect;
  final double marksAwarded;

  const ModelTestAnswer({
    required this.questionId,
    required this.selectedOption,
    required this.isCorrect,
    required this.marksAwarded,
  });

  factory ModelTestAnswer.fromMap(Map<String, dynamic> map) => ModelTestAnswer(
    questionId: map['question_id']?.toString() ?? '',
    selectedOption: map['selected_option']?.toString(),
    isCorrect: map['is_correct'] == true,
    marksAwarded: asDouble(map['marks_awarded']),
  );
}

/// Payload returned by `start_model_test_attempt` (new or resumed attempt).
class ModelTestSession {
  final ModelTestAttempt attempt;
  final List<ModelTestQuestion> questions;
  final Map<String, String> answers;
  final double totalMarks;
  final double marksPerQuestion;
  final double negativeMarks;
  final DateTime? serverNow;
  final bool resumed;

  const ModelTestSession({
    required this.attempt,
    required this.questions,
    required this.answers,
    required this.totalMarks,
    required this.marksPerQuestion,
    required this.negativeMarks,
    required this.serverNow,
    required this.resumed,
  });

  factory ModelTestSession.fromMap(Map<String, dynamic> map) {
    final questions = <ModelTestQuestion>[];
    final rawQuestions = map['questions'];
    if (rawQuestions is List) {
      for (final item in rawQuestions) {
        if (item is Map) {
          questions.add(
            ModelTestQuestion.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final answers = <String, String>{};
    asMap(map['answers']).forEach((key, value) {
      if (value != null) answers[key] = value.toString();
    });
    return ModelTestSession(
      attempt: ModelTestAttempt.fromMap(asMap(map['attempt'])),
      questions: questions,
      answers: answers,
      totalMarks: asDouble(map['total_marks']),
      marksPerQuestion: asDouble(map['marks_per_question'], 1),
      negativeMarks: asDouble(map['negative_marks']),
      serverNow: localTime(map['server_now']),
      resumed: map['resumed'] == true,
    );
  }
}
