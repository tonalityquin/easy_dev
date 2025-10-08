import 'package:flutter/foundation.dart';

@immutable
class OfflineSession {
  final String userId;
  final String name;
  final String position;
  final String phone;
  final String area;
  final DateTime createdAt;

  const OfflineSession({
    required this.userId,
    required this.name,
    required this.position,
    required this.phone,
    required this.area,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
    'user_id': userId,
    'name': name,
    'position': position,
    'phone': phone,
    'area': area,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory OfflineSession.fromMap(Map<String, Object?> map) {
    return OfflineSession(
      userId: (map['user_id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      position: (map['position'] ?? '') as String,
      phone: (map['phone'] ?? '') as String,
      area: (map['area'] ?? '') as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as int?) ?? 0,
      ),
    );
  }
}
