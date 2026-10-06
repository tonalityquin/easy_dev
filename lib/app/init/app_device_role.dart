enum AppDeviceRole {
  tablet,
  sensor,
}

extension AppDeviceRoleValues on AppDeviceRole {
  String get storageValue {
    return switch (this) {
      AppDeviceRole.tablet => 'tablet',
      AppDeviceRole.sensor => 'sensor',
    };
  }

  String get label {
    return switch (this) {
      AppDeviceRole.tablet => '탭/태블릿',
      AppDeviceRole.sensor => '센서',
    };
  }

  String get confirmationLabel {
    return switch (this) {
      AppDeviceRole.tablet => '탭/태블릿',
      AppDeviceRole.sensor => '센서',
    };
  }
}

AppDeviceRole? parseAppDeviceRole(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  for (final role in AppDeviceRole.values) {
    if (role.storageValue == value) return role;
  }
  return null;
}
