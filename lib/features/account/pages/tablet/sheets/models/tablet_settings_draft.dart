
class TabletSettingsDraft {
  const TabletSettingsDraft({
    required this.name,
    required this.codeNumber,
    required this.emailLocal,
    this.permissionKeys = const <String>{},
  });

  final String name;
  final String codeNumber;
  final String emailLocal;
  final Set<String> permissionKeys;

  TabletSettingsDraft copyWith({
    String? name,
    String? codeNumber,
    String? emailLocal,
    Set<String>? permissionKeys,
  }) {
    return TabletSettingsDraft(
      name: name ?? this.name,
      codeNumber: codeNumber ?? this.codeNumber,
      emailLocal: emailLocal ?? this.emailLocal,
      permissionKeys: permissionKeys ?? this.permissionKeys,
    );
  }

  TabletSettingsDraft detached() {
    return TabletSettingsDraft(
      name: name,
      codeNumber: codeNumber,
      emailLocal: emailLocal,
      permissionKeys: permissionKeys,
    );
  }
}
