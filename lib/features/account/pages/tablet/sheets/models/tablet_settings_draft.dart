import '../widgets/tablet_role_type.dart';

class TabletSettingsDraft {
  const TabletSettingsDraft({
    required this.name,
    required this.codeNumber,
    required this.emailLocal,
    required this.role,
  });

  final String name;
  final String codeNumber;
  final String emailLocal;
  final TabletRoleType role;

  TabletSettingsDraft copyWith({
    String? name,
    String? codeNumber,
    String? emailLocal,
    TabletRoleType? role,
  }) {
    return TabletSettingsDraft(
      name: name ?? this.name,
      codeNumber: codeNumber ?? this.codeNumber,
      emailLocal: emailLocal ?? this.emailLocal,
      role: role ?? this.role,
    );
  }

  TabletSettingsDraft detached() {
    return TabletSettingsDraft(
      name: name,
      codeNumber: codeNumber,
      emailLocal: emailLocal,
      role: role,
    );
  }
}
