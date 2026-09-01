import '../widgets/tablet_role_type.dart';

class TabletSettingsDraft {
  const TabletSettingsDraft({
    required this.name,
    required this.phone,
    required this.role,
    required this.password,
  });

  final String name;
  final String phone;
  final TabletRoleType role;
  final String password;

  TabletSettingsDraft copyWith({
    String? name,
    String? phone,
    TabletRoleType? role,
    String? password,
  }) {
    return TabletSettingsDraft(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      password: password ?? this.password,
    );
  }

  TabletSettingsDraft detached() {
    return TabletSettingsDraft(
      name: name,
      phone: phone,
      role: role,
      password: password,
    );
  }
}
