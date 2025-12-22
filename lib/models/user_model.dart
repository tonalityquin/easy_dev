import 'package:flutter/material.dart';

class UserModel {
  final String id;
  final List<String> areas;
  final String? currentArea;
  final List<String> divisions;

  /// ✅ 추가: 계정이 허용하는 모드 목록
  /// Firestore: modes: ["service","lite","simple", ...]
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

  /// ✅ 추가: 계정 활성 상태(soft delete 대체)
  /// - Firestore에 isActive가 없던 기존 데이터는 기본 true로 간주
  final bool isActive;

  const UserModel({
    required this.id,
    required this.areas,
    this.currentArea,
    required this.divisions,

    /// ✅ 기존 생성 코드 영향 최소화를 위해 default []
    this.modes = const [],

    required this.email,
    this.endTime,
    this.englishSelectedAreaName,
    this.fixedHolidays = const [],
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

    /// ✅ 기존 생성 코드 영향 최소화를 위해 default true
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
      englishSelectedAreaName:
      englishSelectedAreaName ?? this.englishSelectedAreaName,
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
      isActive: isActive ?? this.isActive,
    );
  }

  factory UserModel.fromMap(String id, Map<String, dynamic> data) {
    return UserModel(
      id: id,
      areas: List<String>.from(data['areas'] ?? []),
      currentArea: data['currentArea'],
      divisions: List<String>.from(data['divisions'] ?? []),

      /// ✅ 추가
      modes: List<String>.from(data['modes'] ?? []),

      email: data['email'] ?? '',
      endTime: _parseTime(data['endTime']),
      englishSelectedAreaName: data['englishSelectedAreaName'],
      fixedHolidays: List<String>.from(data['fixedHolidays'] ?? []),
      isSaved: data['isSaved'] ?? false,
      isSelected: data['isSelected'] ?? false,
      isWorking: data['isWorking'] ?? false,
      name: data['name'] ?? '',
      password: data['password'] ?? '',
      phone: data['phone'] ?? '',
      position: data['position'],
      role: data['role'] ?? '',
      selectedArea: data['selectedArea'],
      startTime: _parseTime(data['startTime']),

      /// ✅ 추가: 기존 문서에 값이 없으면 true
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'areas': areas,
      'currentArea': currentArea,
      'divisions': divisions,

      /// ✅ 추가
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

      /// ✅ 추가
      'isActive': isActive,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      areas: List<String>.from(json['areas'] ?? []),
      currentArea: json['currentArea'],
      divisions: List<String>.from(json['divisions'] ?? []),

      /// ✅ 추가
      modes: List<String>.from(json['modes'] ?? []),

      email: json['email'] ?? '',
      endTime: _parseTime(json['endTime']),
      englishSelectedAreaName: json['englishSelectedAreaName'],
      fixedHolidays: List<String>.from(json['fixedHolidays'] ?? []),
      isSaved: json['isSaved'] ?? false,
      isSelected: json['isSelected'] ?? false,
      isWorking: json['isWorking'] ?? false,
      name: json['name'] ?? '',
      password: json['password'] ?? '',
      phone: json['phone'] ?? '',
      position: json['position'],
      role: json['role'] ?? '',
      selectedArea: json['selectedArea'],
      startTime: _parseTime(json['startTime']),

      /// ✅ 추가
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'areas': areas,
      'currentArea': currentArea,
      'divisions': divisions,

      /// ✅ 추가
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

      /// ✅ 추가
      'isActive': isActive,
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
