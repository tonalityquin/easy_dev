import 'package:flutter/material.dart';

class UserModel {
  static const List<String> weekdays = <String>['월', '화', '수', '목', '금', '토', '일'];

  final String id;
  final List<String> areas;
  final String? currentArea;
  final List<String> divisions;
  final List<String> modes;
  final String email;
  final TimeOfDay? endTime;
  final String? englishSelectedAreaName;
  final List<String> fixedHolidays;
  final bool isSaved;
  final bool isSelected;
  final bool isWorking;
  final String name;
  final String password;
  final String phone;
  final String? position;
  final String role;
  final String? selectedArea;
  final TimeOfDay? startTime;
  final Map<String, TimeOfDay?> startTimeByWeekday;
  final Map<String, TimeOfDay?> endTimeByWeekday;
  final bool isActive;

  const UserModel({
    required this.id,
    required this.areas,
    this.currentArea,
    required this.divisions,
    this.modes = const <String>[],
    required this.email,
    this.endTime,
    this.englishSelectedAreaName,
    this.fixedHolidays = const <String>[],
    required this.isSaved,
    required this.isSelected,
    required this.isWorking,
    required this.name,
    required this.password,
    required this.phone,
    this.position,
    required this.role,
    this.selectedArea,
    this.startTime,
    this.startTimeByWeekday = const <String, TimeOfDay?>{},
    this.endTimeByWeekday = const <String, TimeOfDay?>{},
    this.isActive = true,
  });

  UserModel copyWith({
    String? id,
    List<String>? areas,
    String? currentArea,
    List<String>? divisions,
    List<String>? modes,
    String? email,
    TimeOfDay? endTime,
    String? englishSelectedAreaName,
    List<String>? fixedHolidays,
    bool? isSaved,
    bool? isSelected,
    bool? isWorking,
    String? name,
    String? password,
    String? phone,
    String? position,
    String? role,
    String? selectedArea,
    TimeOfDay? startTime,
    Map<String, TimeOfDay?>? startTimeByWeekday,
    Map<String, TimeOfDay?>? endTimeByWeekday,
    bool? isActive,
  }) {
    return UserModel(
      id: id ?? this.id,
      areas: areas ?? this.areas,
      currentArea: currentArea ?? this.currentArea,
      divisions: divisions ?? this.divisions,
      modes: modes ?? this.modes,
      email: email ?? this.email,
      endTime: endTime ?? this.endTime,
      englishSelectedAreaName: englishSelectedAreaName ?? this.englishSelectedAreaName,
      fixedHolidays: fixedHolidays ?? this.fixedHolidays,
      isSaved: isSaved ?? this.isSaved,
      isSelected: isSelected ?? this.isSelected,
      isWorking: isWorking ?? this.isWorking,
      name: name ?? this.name,
      password: password ?? this.password,
      phone: phone ?? this.phone,
      position: position ?? this.position,
      role: role ?? this.role,
      selectedArea: selectedArea ?? this.selectedArea,
      startTime: startTime ?? this.startTime,
      startTimeByWeekday: _normalizeWeekdayMap(startTimeByWeekday ?? this.startTimeByWeekday),
      endTimeByWeekday: _normalizeWeekdayMap(endTimeByWeekday ?? this.endTimeByWeekday),
      isActive: isActive ?? this.isActive,
    );
  }

  factory UserModel.fromMap(String id, Map<String, dynamic> data) {
    final fixedHolidays = List<String>.from(data['fixedHolidays'] ?? const <String>[]);
    final startTime = _parseTime(data['startTime']);
    final endTime = _parseTime(data['endTime']);
    final startByWeekday = _decodeWeekdayMap(
      data['startTimeByWeekday'],
      legacyTime: startTime,
      fixedHolidays: fixedHolidays,
    );
    final endByWeekday = _decodeWeekdayMap(
      data['endTimeByWeekday'],
      legacyTime: endTime,
      fixedHolidays: fixedHolidays,
    );

    return UserModel(
      id: id,
      areas: List<String>.from(data['areas'] ?? const <String>[]),
      currentArea: data['currentArea'],
      divisions: List<String>.from(data['divisions'] ?? const <String>[]),
      modes: List<String>.from(data['modes'] ?? const <String>[]),
      email: data['email'] ?? '',
      endTime: endTime ?? _pickRepresentative(endByWeekday),
      englishSelectedAreaName: data['englishSelectedAreaName'],
      fixedHolidays: fixedHolidays,
      isSaved: data['isSaved'] ?? false,
      isSelected: data['isSelected'] ?? false,
      isWorking: data['isWorking'] ?? false,
      name: data['name'] ?? '',
      password: data['password'] ?? '',
      phone: data['phone'] ?? '',
      position: data['position'],
      role: data['role'] ?? '',
      selectedArea: data['selectedArea'],
      startTime: startTime ?? _pickRepresentative(startByWeekday),
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
      'endTime': _timeToMap(endTime),
      'englishSelectedAreaName': englishSelectedAreaName,
      'fixedHolidays': fixedHolidays,
      'isSaved': isSaved,
      'isSelected': isSelected,
      'isWorking': isWorking,
      'name': name,
      'password': password,
      'phone': phone,
      'position': position,
      'role': role,
      'selectedArea': selectedArea,
      'startTime': _timeToMap(startTime),
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
    final out = <String, dynamic>{};
    for (final day in weekdays) {
      out[day] = _timeToMap(map[day]);
    }
    return out;
  }

  static Map<String, TimeOfDay?> _normalizeWeekdayMap(Map<String, TimeOfDay?> map) {
    final out = <String, TimeOfDay?>{};
    for (final day in weekdays) {
      out[day] = map[day];
    }
    return out;
  }

  static Map<String, TimeOfDay?> _decodeWeekdayMap(
    dynamic raw, {
    required TimeOfDay? legacyTime,
    required List<String> fixedHolidays,
  }) {
    final out = <String, TimeOfDay?>{};

    if (raw is Map) {
      for (final day in weekdays) {
        out[day] = _parseTime(raw[day]);
      }
      return out;
    }

    final offDays = fixedHolidays.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    for (final day in weekdays) {
      out[day] = offDays.contains(day) ? null : legacyTime;
    }
    return out;
  }

  static TimeOfDay? _pickRepresentative(Map<String, TimeOfDay?> map) {
    final todayIndex = DateTime.now().weekday - 1;
    if (todayIndex >= 0 && todayIndex < weekdays.length) {
      final today = weekdays[todayIndex];
      final value = map[today];
      if (value != null) {
        return value;
      }
    }
    for (final day in weekdays) {
      final value = map[day];
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
