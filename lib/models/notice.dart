/// Data model for a notice board entry.
///
/// The raw map is preserved so all columns returned by Supabase (including
/// fields such as `target_type` and `target_class`) stay available to the UI.
/// [isRead] is merged in by the repository from the current recipient's
/// `notice_reads` row; it is never stored on `notices` itself because a single
/// notice may be read by one user and still be unread for everybody else.
class Notice {
  final Map<String, dynamic> raw;
  final bool isRead;

  const Notice(this.raw, {this.isRead = false});

  factory Notice.fromMap(Map<String, dynamic> map) => Notice(
    Map<String, dynamic>.from(map),
    isRead: map['is_read'] == true || map['isRead'] == true,
  );

  /// Returns a copy with an updated per-recipient read state. The original raw
  /// Supabase fields are preserved byte-for-byte.
  Notice copyWith({bool? isRead}) =>
      Notice(Map<String, dynamic>.from(raw), isRead: isRead ?? this.isRead);

  String get id => raw['id']?.toString() ?? '';
  String get academyId => raw['academy_id']?.toString() ?? '';
  String get title => raw['title']?.toString() ?? '';
  String get description => raw['description']?.toString() ?? '';

  String get targetType => raw['target_type']?.toString() ?? '';
  String get targetClass => raw['target_class']?.toString() ?? '';

  /// Kept for the existing UI, which still consumes raw maps. The merged
  /// `is_read` value is added so every screen sees the same read state.
  Map<String, dynamic> toMap() => <String, dynamic>{...raw, 'is_read': isRead};
}
