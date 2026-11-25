/// Converts any ASCII digits in a value to Bengali digits.
///
/// Used for counts, durations, marks and countdowns so the study UI reads
/// naturally in Bengali without duplicating formatting logic in every screen.
String bn(dynamic value) {
  const digits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  return value.toString().replaceAllMapped(
    RegExp(r'[0-9]'),
    (match) => digits[int.parse(match.group(0)!)],
  );
}

/// Compact number formatter: `12` stays `১২`, `12.5` becomes `১২.৫`.
String bnNum(double value) {
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
  return bn(text);
}

/// Bengali ordinal used for class/subject positions (`1 -> ১ম`, `2 -> ২য়`).
String bnOrdinal(int rank) {
  if (rank <= 0) return '-';
  final number = bn(rank);
  return switch (rank % 10) {
    2 => '$numberয়',
    3 => '$numberয়',
    4 => '$numberর্থ',
    6 => '$numberষ্ঠ',
    _ => '$numberম',
  };
}
