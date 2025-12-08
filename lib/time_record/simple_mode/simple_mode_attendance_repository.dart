// lib/time_record/simple_mode/simple_mode_attendance_repository.dart
import 'package:intl/intl.dart';

import 'simple_mode_db.dart';

/// 약식 모드 출근/퇴근/휴게 버튼 로그 타입
enum SimpleModeAttendanceType {
  workIn,   // 출근
  workOut,  // 퇴근
  breakTime // 휴게 버튼
}

extension SimpleModeAttendanceTypeX on SimpleModeAttendanceType {
  String get code {
    switch (this) {
      case SimpleModeAttendanceType.workIn:
        return 'work_in';
      case SimpleModeAttendanceType.workOut:
        return 'work_out';
      case SimpleModeAttendanceType.breakTime:
        return 'break';
    }
  }
}

/// DB에 저장된 type 문자열 → Enum 매핑 헬퍼
SimpleModeAttendanceType? simpleModeAttendanceTypeFromCode(String code) {
  switch (code) {
    case 'work_in':
      return SimpleModeAttendanceType.workIn;
    case 'work_out':
      return SimpleModeAttendanceType.workOut;
    case 'break':
      return SimpleModeAttendanceType.breakTime;
  }
  return null;
}

class SimpleModeAttendanceRepository {
  SimpleModeAttendanceRepository._();

  static final SimpleModeAttendanceRepository instance =
  SimpleModeAttendanceRepository._();

  // 예: 2025-12-08
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');

  // 예: 09:00 (항상 두 자리 시각)
  final DateFormat _timeFormatter = DateFormat('HH:mm');

  /// 버튼을 누른 시각을 그대로 한 줄 INSERT
  ///
  /// - 같은 날짜/타입 조합은 항상 **마지막으로 누른 기록만 남도록**
  ///   기존 row를 모두 삭제한 뒤 새 row를 INSERT 한다.
  Future<void> insertEvent({
    required DateTime dateTime,
    required SimpleModeAttendanceType type,
  }) async {
    final db = await SimpleModeDb.instance.database;

    // 'yyyy-MM-dd'
    final date = _dateFormatter.format(dateTime);

    // 'HH:mm' → 9시도 09:00 형식으로 저장
    final time = _timeFormatter.format(dateTime);

    final typeCode = type.code;

    await db.transaction((txn) async {
      // 1) 같은 날짜 + 같은 타입의 기존 로그 모두 삭제
      await txn.delete(
        'simple_mode_attendance',
        where: 'date = ? AND type = ?',
        whereArgs: <Object?>[date, typeCode],
      );

      // 2) 새 로그 1건만 INSERT
      await txn.insert(
        'simple_mode_attendance',
        <String, Object?>{
          'date': date,
          'type': typeCode,
          'time': time,
          'created_at': dateTime.toIso8601String(),
        },
      );
    });
  }

  /// 특정 날짜의 출근/휴게/퇴근 기록을 한 번에 조회
  ///
  /// 반환: { SimpleModeAttendanceType.workIn: '09:12', ... } 형식
  Future<Map<SimpleModeAttendanceType, String>> getEventsForDate(
      DateTime dateTime,
      ) async {
    final db = await SimpleModeDb.instance.database;

    final date = _dateFormatter.format(dateTime); // 'yyyy-MM-dd'

    final rows = await db.query(
      'simple_mode_attendance',
      columns: ['type', 'time'],
      where: 'date = ?',
      whereArgs: <Object?>[date],
    );

    final result = <SimpleModeAttendanceType, String>{};

    for (final row in rows) {
      final typeCode = row['type'] as String;
      final time = row['time'] as String;

      final type = simpleModeAttendanceTypeFromCode(typeCode);
      if (type != null) {
        result[type] = time;
      }
    }

    return result;
  }
}
