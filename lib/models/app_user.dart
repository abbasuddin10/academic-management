/// Data model for the `users` table (admins, teachers and staff).
class AppUser {
  final String id;
  final String? academyId;
  final String email;
  final String fullName;
  final String role;
  final String? phone;
  final double salary;
  final String? photoUrl;
  final String? fcmToken;

  const AppUser({
    required this.id,
    this.academyId,
    required this.email,
    required this.fullName,
    required this.role,
    this.phone,
    this.salary = 0,
    this.photoUrl,
    this.fcmToken,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id']?.toString() ?? '',
      academyId: map['academy_id']?.toString(),
      email: map['email']?.toString() ?? '',
      fullName: (map['full_name'] ?? map['name'] ?? '').toString(),
      role: map['role']?.toString() ?? '',
      phone: map['phone']?.toString(),
      salary: double.tryParse(map['salary']?.toString() ?? '') ?? 0,
      photoUrl: map['photo_url']?.toString(),
      fcmToken: map['fcm_token']?.toString(),
    );
  }

  bool get isSuperAdmin => role == 'super_admin';
  bool get isTeacher => role == 'teacher' || role == 'staff';
}
