// Pure, side-effect-free helpers shared by the admin and student result
// screens. Keeping the math in ONE place guarantees both sides show the same
// marks, percentages and ranks.
//
// Expected JSONB shape in `exam_results`:
//   result_data:      { 'বাংলা_cq': 12, 'বাংলা_mcq': 8,
//                       'বাংলা_viva': 3, 'বাংলা_practical': 10, ... }
//   full_marks_data:  { 'বাংলা': 100, ... }
//
// `viva` is additive: older rows without it simply count as zero.

/// One grading band for the result sheet's reference chart.
class ResultGrade {
  final String label;
  final double min;
  final double max;
  final double point;
  final String remark;

  const ResultGrade(this.label, this.min, this.max, this.point, this.remark);

  String get range => '${min.toInt()}–${max.toInt()}%';
}

abstract final class ResultCalculator {
  /// All supported mark components. Order matters for column rendering.
  static const List<String> components = <String>[
    'cq',
    'mcq',
    'viva',
    'practical',
  ];

  static const List<String> componentLabelsBn = <String>[
    'CQ',
    'MCQ',
    'ভিভা',
    'প্র্যাকটিক্যাল',
  ];

  /// Safely converts a dynamic JSON value into a string-keyed map.
  static Map<String, dynamic> mapOf(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  /// Subject names derived from keys ending in _cq/_mcq/_viva/_practical.
  static Set<String> subjects(Map<String, dynamic> resultData) {
    final found = <String>{};
    for (final key in resultData.keys) {
      for (final component in components) {
        final suffix = '_$component';
        if (key.endsWith(suffix) && key.length > suffix.length) {
          found.add(key.substring(0, key.length - suffix.length));
          break;
        }
      }
    }
    final sorted = found.toList()..sort();
    return sorted.toSet();
  }

  static double mark(
    Map<String, dynamic> data,
    String subject,
    String component,
  ) {
    return double.tryParse(data['${subject}_$component']?.toString() ?? '0') ??
        0;
  }

  static double subjectTotal(Map<String, dynamic> data, String subject) {
    var total = 0.0;
    for (final component in components) {
      total += mark(data, subject, component);
    }
    return total;
  }

  static double subjectFullMark(
    Map<String, dynamic> fullMarksData,
    String subject, {
    double fallback = 100,
  }) {
    final direct = fullMarksData[subject];
    if (direct != null) {
      return double.tryParse(direct.toString()) ?? fallback;
    }
    // Tolerate an alternate legacy key without changing stored data.
    final legacy = fullMarksData['${subject}_full'];
    return double.tryParse(legacy?.toString() ?? '') ?? fallback;
  }

  static Map<String, double> totalsBySubject(Map<String, dynamic> data) => {
    for (final subject in subjects(data)) subject: subjectTotal(data, subject),
  };

  static double obtainedMarks(Map<String, dynamic> data) {
    var total = 0.0;
    for (final value in totalsBySubject(data).values) {
      total += value;
    }
    return total;
  }

  static double fullMarks(
    Map<String, dynamic> data,
    Map<String, dynamic> fullMarksData,
  ) {
    var total = 0.0;
    for (final subject in subjects(data)) {
      total += subjectFullMark(fullMarksData, subject);
    }
    return total;
  }

  /// Returns a 0..1 progress value plus a rounded Bengali-friendly label.
  static ({double value, String label}) percentage(
    Map<String, dynamic> resultData,
    Map<String, dynamic> fullMarksData,
  ) {
    final full = fullMarks(resultData, fullMarksData);
    if (full <= 0) return (value: 0.0, label: '০%');

    final obtained = obtainedMarks(resultData);
    final ratio = (obtained / full).clamp(0.0, 1.0).toDouble();
    return (value: ratio, label: '${(ratio * 100).round()}%');
  }

  static ({double value, String label}) percentageOfRow(
    Map<String, dynamic> row,
  ) {
    return percentage(
      mapOf(row['result_data']),
      mapOf(row['full_marks_data']),
    );
  }

  static bool hasMarks(Map<String, dynamic> data) {
    for (final total in totalsBySubject(data).values) {
      if (total > 0) return true;
    }
    return false;
  }

  static String ordinal(int rank) => switch (rank) {
    1 => '1st',
    2 => '2nd',
    3 => '3rd',
    _ => '${rank}th',
  };

  /// Rank of [myTotal] among the subject totals of [peers].
  /// [peers] MUST already be scoped to academy + exam + class by the caller.
  static String subjectRank(
    List<Map<String, dynamic>> peers,
    String subject,
    double myTotal,
  ) {
    if (myTotal <= 0) return '-';

    final totals = <double>[];
    for (final row in peers) {
      final data = mapOf(row['result_data']);
      if (!subjects(data).contains(subject)) continue;
      final total = subjectTotal(data, subject);
      if (total > 0) totals.add(total);
    }
    if (totals.isEmpty) return '-';

    totals.sort((a, b) => b.compareTo(a));
    var rank = 1;
    for (final total in totals) {
      if (myTotal < total) {
        rank++;
      } else {
        break;
      }
    }
    return ordinal(rank);
  }

  /// Overall class merit of [roll] among [peers].
  /// [peers] MUST already be scoped to academy + exam + class by the caller.
  static String examRank(List<Map<String, dynamic>> peers, String roll) {
    final totalsByRoll = <String, double>{};
    for (final row in peers) {
      final rowRoll = row['roll']?.toString().trim() ?? '';
      if (rowRoll.isEmpty) continue;
      totalsByRoll[rowRoll] = obtainedMarks(mapOf(row['result_data']));
    }

    final mine = totalsByRoll[roll.trim()];
    if (mine == null) return '-';

    final sorted = totalsByRoll.values.toList()..sort((a, b) => b.compareTo(a));
    var rank = 1;
    for (final score in sorted) {
      if (mine < score) {
        rank++;
      } else {
        break;
      }
    }
    return ordinal(rank);
  }

  /// Deterministic merit order (highest total first, then roll ascending).
  /// Used to order result cards so positions are never scrambled.
  static List<String> rankedRolls(List<Map<String, dynamic>> peers) {
    final entries = <MapEntry<String, double>>[];
    for (final row in peers) {
      final roll = row['roll']?.toString().trim() ?? '';
      if (roll.isEmpty) continue;
      entries.add(
        MapEntry(roll, obtainedMarks(mapOf(row['result_data']))),
      );
    }
    entries.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      return a.key.compareTo(b.key); // stable tie-break
    });
    return entries.map((entry) => entry.key).toList();
  }

  /// Position of [roll] in the deterministic merit order.
  static String rollRank(List<Map<String, dynamic>> peers, String roll) {
    final index = rankedRolls(peers).indexOf(roll.trim());
    if (index < 0) return '-';
    return ordinal(index + 1);
  }

  // ---------------------------------------------------------------------------
  // Official 5.0 grading scale (used by the unified result sheet)
  // ---------------------------------------------------------------------------
  static const List<ResultGrade> gradeScale = <ResultGrade>[
    ResultGrade('A+', 80, 100, 5.00, 'Outstanding'),
    ResultGrade('A', 70, 80, 4.00, 'Excellent'),
    ResultGrade('A-', 60, 70, 3.50, 'Very Good'),
    ResultGrade('B', 50, 60, 3.00, 'Good'),
    ResultGrade('C', 40, 50, 2.00, 'Satisfactory'),
    ResultGrade('D', 33, 40, 1.00, 'Pass'),
    ResultGrade('F', 0, 33, 0.00, 'Fail'),
  ];

  /// Pass mark is 33% of a subject's full marks.
  static const double passPercent = 33;

  static ResultGrade gradeFor(double percent) {
    for (final band in gradeScale) {
      if (percent >= band.min && (percent < band.max || band.max == 100)) {
        return band;
      }
    }
    return gradeScale.last;
  }

  /// Subjects scoring below 33% of their full marks are treated as failed.
  static bool hasFailedSubject(
    Map<String, dynamic> resultData,
    Map<String, dynamic> fullMarksData,
  ) {
    for (final subject in subjects(resultData)) {
      final full = subjectFullMark(fullMarksData, subject);
      if (full <= 0) continue;
      final percent = (subjectTotal(resultData, subject) / full) * 100;
      if (percent < passPercent) return true;
    }
    return false;
  }

  /// 5.0-scale GPA. A single failed subject results in GPA 0.00.
  static double gpa(
    Map<String, dynamic> resultData,
    Map<String, dynamic> fullMarksData,
  ) {
    final subjectList = subjects(resultData);
    if (subjectList.isEmpty) return 0;
    if (hasFailedSubject(resultData, fullMarksData)) return 0;

    var total = 0.0;
    for (final subject in subjectList) {
      final full = subjectFullMark(fullMarksData, subject);
      final obtained = subjectTotal(resultData, subject);
      final percent = full > 0 ? (obtained / full) * 100 : 0.0;
      total += gradeFor(percent.clamp(0.0, 100.0)).point;
    }
    return (total / subjectList.length).clamp(0.0, 5.0).toDouble();
  }

  /// Final grade: F when any subject fails, otherwise the overall percentage
  /// grade from the 5.0 scale.
  static ResultGrade overallGrade(
    Map<String, dynamic> resultData,
    Map<String, dynamic> fullMarksData, {
    double? overallPercent,
  }) {
    if (hasFailedSubject(resultData, fullMarksData)) return gradeScale.last;
    final percent = overallPercent ??
        percentage(resultData, fullMarksData).value * 100;
    return gradeFor(percent.clamp(0.0, 100.0));
  }

  /// Case/whitespace-insensitive comparison for class names coming from
  /// different tables (`students.class` vs `exam_results.class_name`).
  static String normalizeClass(String? value) =>
      value?.trim().toLowerCase() ?? '';

  /// Roll comparison tolerant of leading zeros (`01` == `1`).
  static bool sameRoll(String? a, String? b) {
    final left = a?.trim() ?? '';
    final right = b?.trim() ?? '';
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    final leftInt = int.tryParse(left);
    final rightInt = int.tryParse(right);
    return leftInt != null && rightInt != null && leftInt == rightInt;
  }

  /// Selects peers strictly within the same exam AND class.
  static List<Map<String, dynamic>> peersFor({
    required List<Map<String, dynamic>> allResults,
    required String examTitle,
    required String className,
  }) {
    final targetClass = normalizeClass(className);
    return allResults.where((row) {
      final sameExam =
          (row['exam_title']?.toString().trim() ?? '') == examTitle.trim();
      if (!sameExam) return false;
      final rowClass = normalizeClass(row['class_name']?.toString());
      // Rows saved before class_name existed are treated as same-class so a
      // legacy result is never silently excluded from its own ranking pool.
      return rowClass.isEmpty || rowClass == targetClass;
    }).toList();
  }
}
