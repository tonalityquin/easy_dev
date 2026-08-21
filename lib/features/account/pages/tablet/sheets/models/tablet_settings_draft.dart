import '../widgets/tablet_role_type.dart';

class TabletSettingsDraft {
  const TabletSettingsDraft({
    required this.name,
    required this.handle,
    required this.emailLocal,
    required this.role,
    required this.password,
  });

  final String name;
  final String handle;
  final String emailLocal;
  final TabletRoleType role;
  final String password;

  TabletSettingsDraft copyWith({
    String? name,
    String? handle,
    String? emailLocal,
    TabletRoleType? role,
    String? password,
  }) {
    return TabletSettingsDraft(
      name: name ?? this.name,
      handle: handle ?? this.handle,
      emailLocal: emailLocal ?? this.emailLocal,
      role: role ?? this.role,
      password: password ?? this.password,
    );
  }

  TabletSettingsDraft detached() {
    return TabletSettingsDraft(
      name: name,
      handle: handle,
      emailLocal: emailLocal,
      role: role,
      password: password,
    );
  }
}
