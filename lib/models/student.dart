/// Data model for a student record in the `students` table.
///
/// The full Supabase row is retained so screens keep access to every column,
/// while typed getters provide the commonly used values.
class Student {
  final Map<String, dynamic> raw;

  const Student(this.raw);

  factory Student.fromMap(Map<String, dynamic> map) =>
      Student(Map<String, dynamic>.from(map));

  String get id => raw['id']?.toString() ?? '';
  String get academyId => raw['academy_id']?.toString() ?? '';
  String get name => raw['name']?.toString() ?? '';
  String get className => (raw['class'] ?? raw['class_name'])?.toString() ?? '';
  String get roll => raw['roll']?.toString() ?? '';
  double get monthlyFee =>
      double.tryParse(raw['monthly_fee']?.toString() ?? '') ?? 0;

  Map<String, dynamic> toMap() => raw;
}
