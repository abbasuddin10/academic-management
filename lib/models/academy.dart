/// Data model for an academy (tenant) record.
class Academy {
  final String id;
  final String name;
  final String? address;
  final String? phone;
  final String? logoUrl;
  final String? adminEmail;

  const Academy({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.logoUrl,
    this.adminEmail,
  });

  factory Academy.fromMap(Map<String, dynamic> map) {
    return Academy(
      id: map['id']?.toString() ?? '',
      name: (map['academy_name'] ?? map['name'] ?? '').toString(),
      address: map['address']?.toString(),
      phone: map['phone']?.toString(),
      logoUrl: map['logo_url']?.toString(),
      adminEmail: map['admin_email']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'academy_name': name,
        'address': address,
        'logo_url': logoUrl,
        'admin_email': adminEmail,
      };
}
