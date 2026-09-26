import 'attendance_context.dart';

class AttendanceSession {
  const AttendanceSession({
    required this.date,
    required this.userId,
    required this.userName,
    required this.area,
    required this.division,
    required this.contextKey,
    required this.modeKey,
    required this.isHeadquarter,
    required this.clockInAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String date;
  final String userId;
  final String userName;
  final String area;
  final String division;
  final String contextKey;
  final String modeKey;
  final bool isHeadquarter;
  final DateTime clockInAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isValid {
    final normalizedContext = contextKey.trim();
    if (date.trim().isEmpty ||
        userId.trim().isEmpty ||
        userName.trim().isEmpty ||
        area.trim().isEmpty ||
        division.trim().isEmpty ||
        normalizedContext.isEmpty) {
      return false;
    }
    if (isHeadquarter) {
      return normalizedContext == 'headquarter' && modeKey.trim().isEmpty;
    }
    return modeKey.trim().isNotEmpty && normalizedContext == modeKey.trim();
  }

  AttendanceContext toAttendanceContext({required String source}) {
    return AttendanceContext(
      userId: userId,
      userName: userName,
      area: area,
      division: division,
      isHeadquarter: isHeadquarter,
      modeKey: isHeadquarter ? '' : modeKey,
      source: source.trim().isEmpty ? 'attendance_session' : source.trim(),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'date': date,
      'user_id': userId,
      'user_name': userName,
      'area': area,
      'division': division,
      'context_key': contextKey,
      'mode_key': modeKey,
      'is_headquarter': isHeadquarter ? 1 : 0,
      'clock_in_at': clockInAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static AttendanceSession? fromMap(Map<String, Object?> map) {
    final clockInAt = DateTime.tryParse(map['clock_in_at']?.toString() ?? '');
    final createdAt = DateTime.tryParse(map['created_at']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(map['updated_at']?.toString() ?? '');
    if (clockInAt == null || createdAt == null || updatedAt == null) {
      return null;
    }
    final session = AttendanceSession(
      date: map['date']?.toString().trim() ?? '',
      userId: map['user_id']?.toString().trim() ?? '',
      userName: map['user_name']?.toString().trim() ?? '',
      area: map['area']?.toString().trim() ?? '',
      division: map['division']?.toString().trim() ?? '',
      contextKey: map['context_key']?.toString().trim() ?? '',
      modeKey: map['mode_key']?.toString().trim() ?? '',
      isHeadquarter: map['is_headquarter'] == 1 ||
          map['is_headquarter']?.toString() == '1' ||
          map['is_headquarter'] == true,
      clockInAt: clockInAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
    return session.isValid ? session : null;
  }
}
