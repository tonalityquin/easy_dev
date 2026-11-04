
import 'tablet/tablet_model.dart';
import 'user/user_model.dart';

sealed class SessionAccount {
  String get id;
  String get displayName;
  String get role;
  String get currentArea;
  String get selectedArea;
  List<String> get areas;
  List<String> get divisions;
  List<String> get modes;
  String get email;
  String? get position;
  bool get isWorking;
  bool get isTablet;
}

final class UserSessionAccount implements SessionAccount {
  final UserModel user;

  UserSessionAccount(this.user);

  @override
  String get id => user.id;

  @override
  String get displayName => user.name;

  @override
  String get role => user.role;

  @override
  String get currentArea => user.currentArea ?? selectedArea;

  @override
  String get selectedArea => user.selectedArea ?? (user.areas.isNotEmpty ? user.areas.first : '');

  @override
  List<String> get areas => user.areas;

  @override
  List<String> get divisions => user.divisions;

  @override
  List<String> get modes => user.modes;

  @override
  String get email => user.email;

  @override
  String? get position => user.position;

  @override
  bool get isWorking => user.isWorking;

  @override
  bool get isTablet => false;
}

final class TabletSessionAccount implements SessionAccount {
  final TabletModel tablet;

  TabletSessionAccount(this.tablet);

  @override
  String get id => tablet.id;

  @override
  String get displayName => tablet.name;

  @override
  String get role => tablet.role;

  @override
  String get currentArea => tablet.currentArea ?? selectedArea;

  @override
  String get selectedArea => tablet.selectedArea ?? (tablet.areas.isNotEmpty ? tablet.areas.first : '');

  @override
  List<String> get areas => tablet.areas;

  @override
  List<String> get divisions => tablet.divisions;

  @override
  List<String> get modes => const <String>[];

  @override
  String get email => tablet.email;

  @override
  String? get position => tablet.position;

  @override
  bool get isWorking => tablet.isWorking;

  @override
  bool get isTablet => true;
}
