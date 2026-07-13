import 'package:cloud_firestore/cloud_firestore.dart';


class HeadquarterCalendarStaffMember {
  const HeadquarterCalendarStaffMember({
    required this.id,
    required this.name,
    required this.role,
    required this.position,
    required this.division,
    required this.areaName,
  });

  final String id;
  final String name;
  final String role;
  final String position;
  final String division;
  final String areaName;
}

class HeadquarterCalendarReceipt {
  const HeadquarterCalendarReceipt({
    required this.eventId,
    required this.userId,
    required this.userName,
    required this.division,
    required this.areaName,
    required this.acknowledgedAt,
  });

  final String eventId;
  final String userId;
  final String userName;
  final String division;
  final String areaName;
  final DateTime? acknowledgedAt;

  factory HeadquarterCalendarReceipt.fromMap(Map<String, dynamic> data) {
    return HeadquarterCalendarReceipt(
      eventId: _string(data['eventId']),
      userId: _string(data['userId']),
      userName: _string(data['userName']),
      division: _string(data['division']),
      areaName: _string(data['areaName']),
      acknowledgedAt: _date(data['acknowledgedAt']),
    );
  }
}

class HeadquarterCalendarAttendanceResponse {
  const HeadquarterCalendarAttendanceResponse({
    required this.eventId,
    required this.userId,
    required this.userName,
    required this.status,
    required this.updatedAt,
  });

  final String eventId;
  final String userId;
  final String userName;
  final String status;
  final DateTime? updatedAt;

  factory HeadquarterCalendarAttendanceResponse.fromMap(
    Map<String, dynamic> data,
  ) {
    return HeadquarterCalendarAttendanceResponse(
      eventId: _string(data['eventId']),
      userId: _string(data['userId']),
      userName: _string(data['userName']),
      status: _string(data['status']).isEmpty ? 'invited' : _string(data['status']),
      updatedAt: _date(data['updatedAt']),
    );
  }
}

String _string(dynamic value) {
  if (value is String) return value.trim();
  if (value == null) return '';
  return value.toString().trim();
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value.trim());
  return null;
}
