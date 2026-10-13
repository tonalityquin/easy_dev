import '../widgets/tablet_role_type.dart';

class TabletSettingsDraft {
  const TabletSettingsDraft({
    required this.name,
    required this.codeNumber,
    required this.emailLocal,
    required this.role,
    required this.password,
  });

  final String name;
  final String codeNumber;
  final String emailLocal;
  final TabletRoleType role;
  final String password;

  TabletSettingsDraft copyWith({
    String? name,
    String? codeNumber,
    String? emailLocal,
    TabletRoleType? role,
    String? password,
  }) {
    return TabletSettingsDraft(
      name: name ?? this.name,
      codeNumber: codeNumber ?? this.codeNumber,
      emailLocal: emailLocal ?? this.emailLocal,
      role: role ?? this.role,
      password: password ?? this.password,
    );
  }

  TabletSettingsDraft detached() {
    return TabletSettingsDraft(
      name: name,
      codeNumber: codeNumber,
      emailLocal: emailLocal,
      role: role,
      password: password,
    );
  }
}
