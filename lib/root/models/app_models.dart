import 'contact.dart';

class AppModel {
  final String name;
  final String version;

  const AppModel({required this.name, required this.version});
}

class AppState {
  final AppModel appModel;
  final List<Contact> contacts;

  const AppState({required this.appModel, required this.contacts});
}
