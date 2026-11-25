import 'dart:convert';

import 'package:academy_management/models/model_test.dart';
import 'package:academy_management/models/student_model_test_progress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'base_repository.dart';

/// All model-test data access lives here. Scoring, deadlines, attempt
/// ownership and duplicate-submit protection are enforced by the SECURITY
/// DEFINER RPCs in migration 0007 — the client never writes marks directly.
class ModelTestRepository extends BaseRepository {
  /// Guarantees that only a well-formed JSON array string reaches the
  /// json/jsonb column. A malformed value is rejected here with a clear Dart
  /// error instead of surfacing as Postgres "invalid input syntax for json".
  static String _questionIdPayload(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      throw const FormatException('প্রশ্ন আইডি তালিকা খালি।');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        // Drop legacy placeholders such as "—", "-" or "N/A" before encoding.
        // They are not question IDs and must never reach a json/jsonb cast.
        final ids = decoded
            .map((item) => item.toString().trim())
            .where((id) => id.isNotEmpty && !_isPlaceholderId(id))
            .toList();
        if (ids.isNotEmpty) return jsonEncode(ids);
      }
    } catch (_) {
      // Fall through to the same clear error below.
    }
    throw const FormatException('প্রশ্ন আইডি তালিকা সঠিক JSON নয়।');
  }

  static bool _isPlaceholderId(String id) {
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

  static String friendlyError(Object error) {
    final text = error.toString();
    final match = RegExp(r'message:\s*([^,}]+)').firstMatch(text);
    final message = (match?.group(1) ?? text).trim();
    // Postgres exceptions raised in Bengali should reach the user unchanged.
    if (message.contains('Exception') || message.isEmpty) return text;
    return message;
  }

  Future<void> expireTests() async {
    await client.rpc('expire_model_tests');
  }

  /// Client-side mirror of the database overlap trigger (defence in depth).
  /// Returns the conflicting test, or null when the slot is free.
  Future<Map<String, dynamic>?> findOverlap({
    required String academyId,
    required String className,
    required DateTime startAt,
    required DateTime endAt,
    String? excludeTestId,
  }) async {
    final rows = await client
        .from('exam_schedules')
        .select()
        .eq('academy_id', academyId)
        .ilike('class_name', className.trim());
    final startUtc = startAt.toUtc();
    final endUtc = endAt.toUtc();
    for (final row in (rows as List)) {
      final map = Map<String, dynamic>.from(row as Map);
      if (excludeTestId != null && map['id']?.toString() == excludeTestId) {
        continue;
      }
      final status = map['status']?.toString() ?? 'published';
      if (status == 'cancelled' || status == 'expired') continue;
      final otherStart = DateTime.tryParse(map['start_time']?.toString() ?? '');
      final otherEnd = DateTime.tryParse(map['end_time']?.toString() ?? '');
      if (otherStart == null || otherEnd == null) continue;
      if (startUtc.isBefore(otherEnd.toUtc()) &&
          endUtc.isAfter(otherStart.toUtc())) {
        return map;
      }
    }
    return null;
  }

  /// Question IDs from the bank for a class/subject (optionally a chapter).
  Future<List<String>> fetchQuestionIds({
    required String academyId,
    required String className,
    required String subjectName,
    String? chapterName,
    int limit = 40,
  }) async {
    var query = client
        .from('academy_questions')
        .select('id')
        .eq('academy_id', academyId)
        .eq('class_name', className)
        .eq('subject_name', subjectName);
    if (chapterName != null && chapterName.trim().isNotEmpty) {
      query = query.eq('chapter_name', chapterName.trim());
    }
    final rows = await query.limit(limit);
    return (rows as List)
        .map((row) => row['id'].toString())
        .toList(growable: false);
  }

  /// Resolves freshly saved questions by their hashes back to database IDs.
  Future<Map<String, String>> fetchIdsByHashes({
    required String academyId,
    required List<String> hashes,
  }) async {
    if (hashes.isEmpty) return <String, String>{};
    // PostgREST `in()` accepts a Dart list directly.
    final rows = await client
        .from('academy_questions')
        .select('id, question_hash')
        .eq('academy_id', academyId)
        .inFilter('question_hash', hashes);
    final result = <String, String>{};
    for (final row in (rows as List)) {
      final map = Map<String, dynamic>.from(row as Map);
      final hash = map['question_hash']?.toString();
      if (hash != null) result[hash] = map['id'].toString();
    }
    return result;
  }

  /// [includeUnpublished] is for the staff management screen only. Student
  /// screens must leave it false so drafts/cancelled tests are never returned.
  Future<List<ModelTest>> fetchTests({
    required String academyId,
    String? className,
    bool includeUnpublished = false,
  }) async {
    if (academyId.trim().isEmpty) return <ModelTest>[];
    try {
      await expireTests();
    } catch (_) {
      // Legacy backend: the client still uses local end-time checks.
    }

    var query = client
        .from('exam_schedules')
        .select()
        .eq('academy_id', academyId.trim());
    if (className != null && className.trim().isNotEmpty) {
      query = query.ilike('class_name', className.trim());
    }
    final rows = await query.order('created_at', ascending: false);
    return (rows as List)
        .whereType<Map>()
        .map((row) => ModelTest.fromMap(Map<String, dynamic>.from(row)))
        // Defence in depth: a draft must NEVER reach a student screen, even
        // on a backend where the stricter RLS policy was not applied.
        .where(
          (test) => includeUnpublished || test.isPublished || test.isExpired,
        )
        .toList();
  }

  Future<ModelTest?> fetchTest(String testId) async {
    final rows = await client
        .from('exam_schedules')
        .select()
        .eq('id', testId)
        .limit(1);
    if (rows.isEmpty) return null;
    return ModelTest.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<ModelTestSession> startAttempt(String testId) async {
    final result = await client.rpc(
      'start_model_test_attempt',
      params: {'p_test_id': testId},
    );
    return ModelTestSession.fromMap(Map<String, dynamic>.from(result as Map));
  }

  Future<void> saveAnswer({
    required String attemptId,
    required String questionId,
    String? selectedOption,
  }) async {
    await client.rpc(
      'save_model_test_answer',
      params: {
        'p_attempt_id': attemptId,
        'p_question_id': questionId,
        'p_selected_option': selectedOption,
      },
    );
  }

  Future<Map<String, dynamic>> submitAttempt(
    String attemptId, {
    bool auto = false,
  }) async {
    final result = await client.rpc(
      'submit_model_test_attempt',
      params: {'p_attempt_id': attemptId, 'p_auto': auto},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<ModelTestAttempt>> fetchAttempts({
    required String academyId,
    String? studentId,
    String? testId,
  }) async {
    if (academyId.trim().isEmpty) return <ModelTestAttempt>[];
    var query = client
        .from('model_test_attempts')
        .select()
        .eq('academy_id', academyId.trim());
    if (studentId != null && studentId.trim().isNotEmpty) {
      query = query.eq('student_id', studentId.trim());
    }
    if (testId != null && testId.trim().isNotEmpty) {
      query = query.eq('test_id', testId);
    }
    final rows = await query.order('started_at', ascending: false);
    return (rows as List)
        .whereType<Map>()
        .map((row) => ModelTestAttempt.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Aggregate progress and class positions for the signed-in student.
  ///
  /// The RPC validates the tenant/session itself and returns only aggregate
  /// ranks — never another student's answers or private details.
  Future<StudentModelTestProgress> fetchStudentProgress({
    required String academyId,
    required String className,
  }) async {
    if (academyId.trim().isEmpty) return StudentModelTestProgress.empty();
    final result = await client.rpc(
      'student_model_test_progress',
      params: {
        'p_academy_id': academyId.trim(),
        'p_class_name': className.trim(),
      },
    );
    // PostgREST normally decodes jsonb to Map, but older gateways can return
    // JSON text. Treat anything else as an empty report instead of throwing.
    Object? payload = result;
    if (payload is String && payload.trim().isNotEmpty) {
      try {
        payload = jsonDecode(payload);
      } catch (_) {
        return StudentModelTestProgress.empty();
      }
    }
    return StudentModelTestProgress.fromObject(payload);
  }

  Future<ModelTestAttempt?> fetchAttempt(String attemptId) async {
    final rows = await client
        .from('model_test_attempts')
        .select()
        .eq('id', attemptId)
        .limit(1);
    if (rows.isEmpty) return null;
    return ModelTestAttempt.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<List<ModelTestAnswer>> fetchAnswers(String attemptId) async {
    final rows = await client
        .from('model_test_answers')
        .select()
        .eq('attempt_id', attemptId);
    return (rows as List)
        .whereType<Map>()
        .map((row) => ModelTestAnswer.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Map<String, dynamic> _testParams({
    required String? testId,
    required String academyId,
    required String className,
    required String subjectName,
    required String examTitle,
    required String? chapterName,
    required String selectedQuestionIds,
    required DateTime startAt,
    required DateTime endAt,
    required String status,
    required String creatorId,
    required String creatorName,
    required int durationMinutes,
    required double marksPerQuestion,
    required double totalMarks,
    required double negativeMarks,
    required double passPercent,
  }) => <String, dynamic>{
    'p_test_id': testId,
    'p_academy_id': academyId,
    'p_class_name': className,
    'p_subject_name': subjectName,
    'p_exam_title': examTitle,
    'p_chapter_name': chapterName,
    'p_selected_question_ids': _questionIdPayload(selectedQuestionIds),
    'p_start_time': startAt.toUtc().toIso8601String(),
    'p_end_time': endAt.toUtc().toIso8601String(),
    'p_status': status,
    'p_duration_minutes': durationMinutes,
    'p_marks_per_question': marksPerQuestion,
    'p_total_marks': totalMarks,
    'p_negative_marks': negativeMarks,
    'p_pass_percent': passPercent,
    'p_creator_id': creatorId.isEmpty ? null : creatorId,
    'p_creator_name': creatorName,
  };

  /// Writes through the JSON-safe RPC in migration 0012. A direct insert is
  /// kept only as a fallback for a backend where the RPC is not deployed yet.
  Future<String> createTest({
    required String academyId,
    required String className,
    required String subjectName,
    required String examTitle,
    required String? chapterName,
    required String selectedQuestionIds,
    required DateTime startAt,
    required DateTime endAt,
    required String status,
    required String creatorId,
    required String creatorName,
    required int durationMinutes,
    required double marksPerQuestion,
    required double totalMarks,
    required double negativeMarks,
    required double passPercent,
  }) async {
    final params = _testParams(
      testId: null,
      academyId: academyId,
      className: className,
      subjectName: subjectName,
      examTitle: examTitle,
      chapterName: chapterName,
      selectedQuestionIds: selectedQuestionIds,
      startAt: startAt,
      endAt: endAt,
      status: status,
      creatorId: creatorId,
      creatorName: creatorName,
      durationMinutes: durationMinutes,
      marksPerQuestion: marksPerQuestion,
      totalMarks: totalMarks,
      negativeMarks: negativeMarks,
      passPercent: passPercent,
    );
    try {
      final result = await client.rpc('save_model_test', params: params);
      return result?.toString() ?? '';
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202' &&
          !error.message.toLowerCase().contains('save_model_test')) {
        rethrow;
      }
      final rows = await client
          .from('exam_schedules')
          .insert({
            'academy_id': academyId,
            'class_name': className,
            'subject_name': subjectName,
            'exam_title': examTitle,
            'chapter_name': chapterName,
            'selected_question_ids': _questionIdPayload(selectedQuestionIds),
            'question_count': 0,
            'start_time': startAt.toUtc().toIso8601String(),
            'end_time': endAt.toUtc().toIso8601String(),
            'status': status,
            'duration_minutes': durationMinutes,
            'marks_per_question': marksPerQuestion,
            'total_marks': totalMarks,
            'negative_marks': negativeMarks,
            'pass_percent': passPercent,
            'question_creator_id': creatorId.isEmpty ? null : creatorId,
            'question_creator_name': creatorName,
          })
          .select('id');
      return rows.first['id'].toString();
    }
  }

  Future<void> updateTest({
    required String testId,
    required String examTitle,
    required String? chapterName,
    required String? selectedQuestionIds,
    required DateTime startAt,
    required DateTime endAt,
    required String status,
    required int durationMinutes,
    required double marksPerQuestion,
    required double totalMarks,
    required double negativeMarks,
    required double passPercent,
  }) async {
    final rows = await client
        .from('exam_schedules')
        .select()
        .eq('id', testId)
        .limit(1);
    final existing = rows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(rows.first as Map);
    // Question set is immutable once students started — reuse the stored IDs.
    // A jsonb column arrives as a Dart List; toString() would produce
    // "[id1, id2]" which is NOT valid JSON. Always normalise to a JSON array
    // string before sending it to the RPC.
    final String ids =
        selectedQuestionIds ??
        normalizeJsonIdArray(existing['selected_question_ids']);
    final params = _testParams(
      testId: testId,
      academyId: existing['academy_id']?.toString() ?? '',
      className: existing['class_name']?.toString() ?? '',
      subjectName: existing['subject_name']?.toString() ?? '',
      examTitle: examTitle,
      chapterName: chapterName,
      selectedQuestionIds: ids,
      startAt: startAt,
      endAt: endAt,
      status: status,
      creatorId: existing['question_creator_id']?.toString() ?? '',
      creatorName: existing['question_creator_name']?.toString() ?? 'Teacher',
      durationMinutes: durationMinutes,
      marksPerQuestion: marksPerQuestion,
      totalMarks: totalMarks,
      negativeMarks: negativeMarks,
      passPercent: passPercent,
    );
    try {
      await client.rpc('save_model_test', params: params);
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202' &&
          !error.message.toLowerCase().contains('save_model_test')) {
        rethrow;
      }
      await client
          .from('exam_schedules')
          .update(<String, dynamic>{
            'exam_title': examTitle,
            'chapter_name': chapterName,
            'start_time': startAt.toUtc().toIso8601String(),
            'end_time': endAt.toUtc().toIso8601String(),
            'status': status,
            'duration_minutes': durationMinutes,
            'marks_per_question': marksPerQuestion,
            'total_marks': totalMarks,
            'negative_marks': negativeMarks,
            'pass_percent': passPercent,
          })
          .eq('id', testId);
    }
  }

  Future<void> setStatus(String testId, String status) async {
    await client
        .from('exam_schedules')
        .update({'status': status})
        .eq('id', testId);
  }

  Future<void> deleteTest({
    required String testId,
    required String academyId,
  }) async {
    await client
        .from('exam_schedules')
        .delete()
        .eq('id', testId)
        .eq('academy_id', academyId);
  }

  /// Saves a bank question through the hardening RPC (migration 0008).
  ///
  /// The RPC writes only columns that exist in the live legacy table and
  /// fills author metadata itself, so a NOT NULL legacy column can no longer
  /// make the save fail silently. If the migration has not been applied yet we
  /// fall back to the original direct insert and surface any error clearly.
  Future<String> saveQuestion({
    required String academyId,
    required String className,
    required String subjectName,
    required String chapterName,
    required String questionText,
    required String optionA,
    required String optionB,
    required String optionC,
    required String optionD,
    required String correctOption,
    required String explanation,
    required String questionHash,
  }) async {
    final params = <String, dynamic>{
      'p_academy_id': academyId,
      'p_class_name': className,
      'p_subject_name': subjectName,
      'p_chapter_name': chapterName,
      'p_question_text': questionText,
      'p_option_a': optionA,
      'p_option_b': optionB,
      'p_option_c': optionC,
      'p_option_d': optionD,
      'p_correct_option': correctOption,
      'p_explanation': explanation,
      'p_question_hash': questionHash,
    };
    try {
      final result = await client.rpc('save_academy_question', params: params);
      return result?.toString() ?? '';
    } on PostgrestException catch (error) {
      final missingFunction =
          error.code == 'PGRST202' ||
          error.message.toLowerCase().contains('save_academy_question');
      if (!missingFunction) rethrow;

      final rows = await client
          .from('academy_questions')
          .insert({
            'academy_id': academyId,
            'class_name': className,
            'subject_name': subjectName,
            'chapter_name': chapterName,
            'question_text': questionText,
            'option_a': optionA,
            'option_b': optionB,
            'option_c': optionC,
            'option_d': optionD,
            'correct_option': correctOption,
            'explanation': explanation,
            'question_hash': questionHash,
          })
          .select('id');
      return rows.first['id'].toString();
    }
  }

  /// True when a question with the same hash already exists for this scope.
  /// Uses a bounded list instead of maybeSingle(), which throws when legacy
  /// duplicate rows already exist.
  Future<bool> questionExists({
    required String academyId,
    required String className,
    required String subjectName,
    required String questionHash,
  }) async {
    final rows = await client
        .from('academy_questions')
        .select('id')
        .eq('academy_id', academyId)
        .eq('class_name', className)
        .eq('subject_name', subjectName)
        .eq('question_hash', questionHash)
        .limit(1);
    return rows.isNotEmpty;
  }
}
