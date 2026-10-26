import 'package:flutter/material.dart';

import '../../../../../../shared/auth/account_code_number.dart';

class UserSettingsDraft {
  UserSettingsDraft({
    required this.name,
    required this.codeNumber,
    required this.codeEntryMode,
    required this.emailLocal,
    required this.position,
    Set<String> permissionKeys = const <String>{},
    required Set<String> modes,
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
    required Set<String> breakDays,
  })  : permissionKeys = Set<String>.unmodifiable(permissionKeys),
        modes = Set<String>.unmodifiable(modes),
        startByDay = Map<String, TimeOfDay?>.unmodifiable(startByDay),
        endByDay = Map<String, TimeOfDay?>.unmodifiable(endByDay),
        breakDays = Set<String>.unmodifiable(breakDays);

  final String name;
  final String codeNumber;
  final UserCodeEntryMode codeEntryMode;
  final String emailLocal;
  final String position;
  final Set<String> permissionKeys;
  final Set<String> modes;
  final Map<String, TimeOfDay?> startByDay;
  final Map<String, TimeOfDay?> endByDay;
  final Set<String> breakDays;

  UserSettingsDraft copyWith({
    String? name,
    String? codeNumber,
    UserCodeEntryMode? codeEntryMode,
    String? emailLocal,
    String? position,
    Set<String>? permissionKeys,
    Set<String>? modes,
    Map<String, TimeOfDay?>? startByDay,
    Map<String, TimeOfDay?>? endByDay,
    Set<String>? breakDays,
  }) {
    return UserSettingsDraft(
      name: name ?? this.name,
      codeNumber: codeNumber ?? this.codeNumber,
      codeEntryMode: codeEntryMode ?? this.codeEntryMode,
      emailLocal: emailLocal ?? this.emailLocal,
      position: position ?? this.position,
      permissionKeys: permissionKeys ?? this.permissionKeys,
      modes: modes ?? this.modes,
      startByDay: startByDay ?? this.startByDay,
      endByDay: endByDay ?? this.endByDay,
      breakDays: breakDays ?? this.breakDays,
    );
  }

  UserSettingsDraft detached() {
    return UserSettingsDraft(
      name: name,
      codeNumber: codeNumber,
      codeEntryMode: codeEntryMode,
      emailLocal: emailLocal,
      position: position,
      permissionKeys: permissionKeys,
      modes: modes,
      startByDay: startByDay,
      endByDay: endByDay,
      breakDays: breakDays,
    );
  }
}
