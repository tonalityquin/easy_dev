import 'package:flutter/material.dart';

import '../widgets/user_role_type_section.dart';

class UserSettingsDraft {
  UserSettingsDraft({
    required this.name,
    required this.phone,
    required this.emailLocal,
    required this.position,
    required this.password,
    required this.role,
    required Set<String> modes,
    required Map<String, TimeOfDay?> startByDay,
    required Map<String, TimeOfDay?> endByDay,
    required Set<String> breakDays,
  })  : modes = Set<String>.unmodifiable(modes),
        startByDay = Map<String, TimeOfDay?>.unmodifiable(startByDay),
        endByDay = Map<String, TimeOfDay?>.unmodifiable(endByDay),
        breakDays = Set<String>.unmodifiable(breakDays);

  final String name;
  final String phone;
  final String emailLocal;
  final String position;
  final String password;
  final RoleType role;
  final Set<String> modes;
  final Map<String, TimeOfDay?> startByDay;
  final Map<String, TimeOfDay?> endByDay;
  final Set<String> breakDays;

  UserSettingsDraft copyWith({
    String? name,
    String? phone,
    String? emailLocal,
    String? position,
    String? password,
    RoleType? role,
    Set<String>? modes,
    Map<String, TimeOfDay?>? startByDay,
    Map<String, TimeOfDay?>? endByDay,
    Set<String>? breakDays,
  }) {
    return UserSettingsDraft(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      emailLocal: emailLocal ?? this.emailLocal,
      position: position ?? this.position,
      password: password ?? this.password,
      role: role ?? this.role,
      modes: modes ?? this.modes,
      startByDay: startByDay ?? this.startByDay,
      endByDay: endByDay ?? this.endByDay,
      breakDays: breakDays ?? this.breakDays,
    );
  }

  UserSettingsDraft detached() {
    return UserSettingsDraft(
      name: name,
      phone: phone,
      emailLocal: emailLocal,
      position: position,
      password: password,
      role: role,
      modes: modes,
      startByDay: startByDay,
      endByDay: endByDay,
      breakDays: breakDays,
    );
  }
}
