import 'package:hive/hive.dart';

part 'contact.g.dart';

@HiveType(typeId: 0)
class Contact {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final List<String> phones;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  int? studentId;

  @HiveField(4)
  bool isDeleted;

  Contact({
    required this.name,
    required this.phones,
    DateTime? createdAt,
    this.studentId,
    this.isDeleted = false,
  }) : createdAt = createdAt ?? DateTime.now();
}