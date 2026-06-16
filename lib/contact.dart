class Contact {
  final String name;
  final String phone;
  final DateTime createdAt;

  Contact({
    required this.name,
    required this.phone,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
