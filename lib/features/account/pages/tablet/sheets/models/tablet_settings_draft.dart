import '../widgets/tablet_role_type.dart';

class TabletSettingsDraft {
  const TabletSettingsDraft({
    required this.name,
    required this.codeNumber,
    required this.role,
    required this.password,
  });

  final String name;
  final String codeNumber;
  final TabletRoleType role;
  final String password;

  TabletSettingsDraft copyWith({
    String? name,
    String? codeNumber,
    TabletRoleType? role,
    String? password,
  }) {
    return TabletSettingsDraft(
      name: name ?? this.name,
      codeNumber: codeNumber ?? this.codeNumber,
      role: role ?? this.role,
      password: password ?? this.password,
    );
  }

  TabletSettingsDraft detached() {
    return TabletSettingsDraft(
      name: name,
      codeNumber: codeNumber,
      role: role,
      password: password,
    );
  }
}
