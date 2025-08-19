import 'package:flutter/material.dart';

class UserModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String role;
  final String password;
  final String? position;

  final List<String> areas;
  final List<String> divisions;

  final String? currentArea;
  final String? selectedArea;
  final String? englishSelectedAreaName;

  final bool isSelected;
  final bool isWorking;
  final bool isSaved;

  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final List<String> fixedHolidays;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.password,
    this.position,
    required this.areas,
    required this.divisions,
    this.currentArea,
    this.selectedArea,
    this.englishSelectedAreaName,
    required this.isSelected,
    required this.isWorking,
    required this.isSaved,
    this.startTime,
    this.endTime,
    this.fixedHolidays = const [],
  });

  UserModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? role,
    String? password,
    String? position,
    List<String>? areas,
    List<String>? divisions,
    String? currentArea,
    String? selectedArea,
    String? englishSelectedAreaName,
    bool? isSelected,
    bool? isWorking,
    bool? isSaved,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    List<String>? fixedHolidays,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      password: password ?? this.password,
      position: position ?? this.position,
      areas: areas ?? this.areas,
      divisions: divisions ?? this.divisions,
      currentArea: currentArea ?? this.currentArea,
      selectedArea: selectedArea ?? this.selectedArea,
      englishSelectedAreaName: englishSelectedAreaName ?? this.englishSelectedAreaName,
      isSelected: isSelected ?? this.isSelected,
      isWorking: isWorking ?? this.isWorking,
      isSaved: isSaved ?? this.isSaved,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      fixedHolidays: fixedHolidays ?? this.fixedHolidays,
    );
  }

  factory UserModel.fromMap(String id, Map<String, dynamic> data) {
    return UserModel(
      id: id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? '',
      password: data['password'] ?? '',
      position: data['position'],
      areas: List<String>.from(data['areas'] ?? []),
      divisions: List<String>.from(data['divisions'] ?? []),
      currentArea: data['currentArea'],
      selectedArea: data['selectedArea'],
      englishSelectedAreaName: data['englishSelectedAreaName'],
      isSelected: data['isSelected'] ?? false,
      isWorking: data['isWorking'] ?? false,
      isSaved: data['isSaved'] ?? false,
      startTime: _parseTime(data['startTime']),
      endTime: _parseTime(data['endTime']),
      fixedHolidays: List<String>.from(data['fixedHolidays'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'password': password,
      'position': position,
      'areas': areas,
      'divisions': divisions,
      'currentArea': currentArea,
      'selectedArea': selectedArea,
      'englishSelectedAreaName': englishSelectedAreaName,
      'isSelected': isSelected,
      'isWorking': isWorking,
      'isSaved': isSaved,
      'startTime': _timeToMap(startTime),
      'endTime': _timeToMap(endTime),
      'fixedHolidays': fixedHolidays,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      password: json['password'] ?? '',
      position: json['position'],
      areas: List<String>.from(json['areas'] ?? []),
      divisions: List<String>.from(json['divisions'] ?? []),
      currentArea: json['currentArea'],
      selectedArea: json['selectedArea'],
      englishSelectedAreaName: json['englishSelectedAreaName'],
      isSelected: json['isSelected'] ?? false,
      isWorking: json['isWorking'] ?? false,
      isSaved: json['isSaved'] ?? false,
      startTime: _parseTime(json['startTime']),
      endTime: _parseTime(json['endTime']),
      fixedHolidays: List<String>.from(json['fixedHolidays'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'password': password,
      'position': position,
      'areas': areas,
      'divisions': divisions,
      'currentArea': currentArea,
      'selectedArea': selectedArea,
      'englishSelectedAreaName': englishSelectedAreaName,
      'isSelected': isSelected,
      'isWorking': isWorking,
      'isSaved': isSaved,
      'startTime': _timeToMap(startTime),
      'endTime': _timeToMap(endTime),
      'fixedHolidays': fixedHolidays,
    };
  }

  Map<String, dynamic> toMapWithId() => toJson();

  static Map<String, int>? _timeToMap(TimeOfDay? time) {
    if (time == null) return null;
    return {'hour': time.hour, 'minute': time.minute};
  }

  static TimeOfDay? _parseTime(dynamic timeData) {
    if (timeData is Map<String, dynamic>) {
      final hour = timeData['hour'];
      final minute = timeData['minute'];
      if (hour is int && minute is int) {
        return TimeOfDay(hour: hour, minute: minute);
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
