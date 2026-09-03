import 'package:flutter/material.dart';

class UserModel {
  static const List<String> weekdays = <String>['월', '화', '수', '목', '금', '토', '일'];

  final String id;
  final List<String> areas;
  final String? currentArea;
  final List<String> divisions;
  final List<String> modes;
  final String email;
  final String? englishSelectedAreaName;
  final List<String> fixedHolidays;
  final List<String> breakDays;
  final bool isSaved;
  final bool isSelected;
  final bool isWorking;
  final String name;
  final String password;
  final String phone;
  final String? position;
  final String role;
  final String? selectedArea;
  final Map<String, TimeOfDay?> startTimeByWeekday;
  final Map<String, TimeOfDay?> endTimeByWeekday;
  final bool isActive;

  UserModel({
    required this.id,
    required this.areas,
    this.currentArea,
    required this.divisions,
    this.modes = const <String>[],
    required this.email,
    this.englishSelectedAreaName,
    List<String> breakDays = const <String>[],
    required this.isSaved,
    required this.isSelected,
    required this.isWorking,
    required this.name,
    required this.password,
    required this.phone,
    this.position,
    required this.role,
    this.selectedArea,
    Map<String, TimeOfDay?> startTimeByWeekday = const <String, TimeOfDay?>{},
    Map<String, TimeOfDay?> endTimeByWeekday = const <String, TimeOfDay?>{},
    this.isActive = true,
  })  : startTimeByWeekday = _normalizeWeekdayMap(startTimeByWeekday),
        endTimeByWeekday = _normalizeWeekdayMap(endTimeByWeekday),
        fixedHolidays = _deriveFixedHolidays(
          _normalizeWeekdayMap(startTimeByWeekday),
          _normalizeWeekdayMap(endTimeByWeekday),
        ),
        breakDays = _normalizeDayList(breakDays);

  UserModel copyWith({
    String? id,
    List<String>? areas,
    String? currentArea,
    List<String>? divisions,
    List<String>? modes,
    String? email,
    String? englishSelectedAreaName,
    List<String>? breakDays,
    bool? isSaved,
    bool? isSelected,
    bool? isWorking,
    String? name,
    String? password,
    String? phone,
    String? position,
    String? role,
    String? selectedArea,
    Map<String, TimeOfDay?>? startTimeByWeekday,
    Map<String, TimeOfDay?>? endTimeByWeekday,
    bool? isActive,
  }) {
    final nextStart = _normalizeWeekdayMap(startTimeByWeekday ?? this.startTimeByWeekday);
    final nextEnd = _normalizeWeekdayMap(endTimeByWeekday ?? this.endTimeByWeekday);
    return UserModel(
      id: id ?? this.id,
      areas: areas ?? this.areas,
      currentArea: currentArea ?? this.currentArea,
      divisions: divisions ?? this.divisions,
      modes: modes ?? this.modes,
      email: email ?? this.email,
      englishSelectedAreaName: englishSelectedAreaName ?? this.englishSelectedAreaName,
      breakDays: breakDays ?? this.breakDays,
      isSaved: isSaved ?? this.isSaved,
      isSelected: isSelected ?? this.isSelected,
      isWorking: isWorking ?? this.isWorking,
      name: name ?? this.name,
      password: password ?? this.password,
      phone: phone ?? this.phone,
      position: position ?? this.position,
      role: role ?? this.role,
      selectedArea: selectedArea ?? this.selectedArea,
      startTimeByWeekday: nextStart,
      endTimeByWeekday: nextEnd,
      isActive: isActive ?? this.isActive,
    );
  }

  factory UserModel.fromMap(String id, Map<String, dynamic> data) {
    final legacyFixedHolidays = _decodeDayList(data['fixedHolidays']);
    final startByWeekday = _decodeWeekdayMap(
      data['startTimeByWeekday'],
      legacyTime: _parseTime(data['startTime']),
      fixedHolidays: legacyFixedHolidays,
    );
    final endByWeekday = _decodeWeekdayMap(
      data['endTimeByWeekday'],
      legacyTime: _parseTime(data['endTime']),
      fixedHolidays: legacyFixedHolidays,
    );
    final breakDays = data.containsKey('breakDays')
        ? _decodeDayList(data['breakDays'])
        : _inferBreakDays(
            startByWeekday: startByWeekday,
            endByWeekday: endByWeekday,
            fixedHolidays: legacyFixedHolidays,
          );

    return UserModel(
      id: id,
      areas: List<String>.from(data['areas'] ?? const <String>[]),
      currentArea: data['currentArea'],
      divisions: List<String>.from(data['divisions'] ?? const <String>[]),
      modes: List<String>.from(data['modes'] ?? const <String>[]),
      email: data['email'] ?? '',
      englishSelectedAreaName: data['englishSelectedAreaName'],
      breakDays: breakDays,
      isSaved: data['isSaved'] ?? false,
      isSelected: data['isSelected'] ?? false,
      isWorking: data['isWorking'] ?? false,
      name: data['name'] ?? '',
      password: data['password'] ?? '',
      phone: data['phone'] ?? '',
      position: data['position'],
      role: data['role'] ?? '',
      selectedArea: data['selectedArea'],
      startTimeByWeekday: startByWeekday,
      endTimeByWeekday: endByWeekday,
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'areas': areas,
      'currentArea': currentArea,
      'divisions': divisions,
      'modes': modes,
      'email': email,
      'englishSelectedAreaName': englishSelectedAreaName,
      'fixedHolidays': fixedHolidays,
      'breakDays': breakDays,
      'isSaved': isSaved,
      'isSelected': isSelected,
      'isWorking': isWorking,
      'name': name,
      'password': password,
      'phone': phone,
      'position': position,
      'role': role,
      'selectedArea': selectedArea,
      'startTimeByWeekday': _encodeWeekdayMap(startTimeByWeekday),
      'endTimeByWeekday': _encodeWeekdayMap(endTimeByWeekday),
      'isActive': isActive,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel.fromMap(json['id'] ?? '', json);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      ...toMap(),
    };
  }

  Map<String, dynamic> toMapWithId() => toJson();

  static Map<String, int>? _timeToMap(TimeOfDay? time) {
    if (time == null) return null;
    return <String, int>{'hour': time.hour, 'minute': time.minute};
  }

  static TimeOfDay? _parseTime(dynamic timeData) {
    if (timeData is Map) {
      final hour = timeData['hour'];
      final minute = timeData['minute'];
      if (hour is int && minute is int) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }
    return null;
  }

  static Map<String, dynamic> _encodeWeekdayMap(Map<String, TimeOfDay?> map) {
    return <String, dynamic>{
      for (final day in weekdays) day: _timeToMap(map[day]),
    };
  }

  static Map<String, TimeOfDay?> _normalizeWeekdayMap(Map<String, TimeOfDay?> map) {
    return <String, TimeOfDay?>{
      for (final day in weekdays) day: map[day],
    };
  }

  static List<String> _deriveFixedHolidays(
    Map<String, TimeOfDay?> startByWeekday,
    Map<String, TimeOfDay?> endByWeekday,
  ) {
    return <String>[
      for (final day in weekdays)
        if (startByWeekday[day] == null && endByWeekday[day] == null) day,
    ];
  }

  static List<String> _decodeDayList(dynamic raw) {
    if (raw is Iterable) {
      return _normalizeDayList(raw.map((value) => value.toString()));
    }
    if (raw is Map) {
      final out = <String>[];
      for (final day in weekdays) {
        if (raw[day] == true) out.add(day);
      }
      return out;
    }
    return const <String>[];
  }

  static List<String> _normalizeDayList(Iterable<String> raw) {
    final set = raw.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
    return <String>[
      for (final day in weekdays)
        if (set.contains(day)) day,
      for (final value in set)
        if (!weekdays.contains(value)) value,
    ];
  }

  static Map<String, TimeOfDay?> _decodeWeekdayMap(
    dynamic raw, {
    required TimeOfDay? legacyTime,
    required List<String> fixedHolidays,
  }) {
    if (raw is Map) {
      return <String, TimeOfDay?>{
        for (final day in weekdays) day: _parseTime(raw[day]),
      };
    }

    final offDays = fixedHolidays.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
    return <String, TimeOfDay?>{
      for (final day in weekdays) day: offDays.contains(day) ? null : legacyTime,
    };
  }

  static List<String> _inferBreakDays({
    required Map<String, TimeOfDay?> startByWeekday,
    required Map<String, TimeOfDay?> endByWeekday,
    required List<String> fixedHolidays,
  }) {
    final holidays = fixedHolidays.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
    return <String>[
      for (final day in weekdays)
        if (!holidays.contains(day) && startByWeekday[day] != null && endByWeekday[day] != null) day,
    ];
  }

}