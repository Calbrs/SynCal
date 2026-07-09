import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'contact_group.g.dart';

@HiveType(typeId: 108)
class ContactGroup extends HiveObject {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  String name;
  
  /// Stores the Hive keys (as Strings) of the Contacts belonging to this group.
  @HiveField(2)
  List<String> contactKeys;

  @HiveField(3)
  final DateTime createdAt;

  ContactGroup({
    String? id,
    required this.name,
    required this.contactKeys,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();
}
