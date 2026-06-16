import 'package:hive_flutter/hive_flutter.dart';

part 'contact.g.dart';

@HiveType(typeId: 0)
class Contact {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final List<String> phones;

  @HiveField(2)
  final DateTime createdAt;

  Contact({
    required this.name,
    required this.phones,
    required this.createdAt,
  });
}