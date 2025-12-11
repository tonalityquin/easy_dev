// lib/time_record/simple_mode/simple_mode_attendance_repository.dart
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart'; // ✅ ConflictAlgorithm 사용

import 'simple_mode_db.dart';

// ✅ Firestore 연동용 레포지토리 (경로는 실제 프로젝트 구조에 맞게 조정)
import 'package:easydev/repositories/commute_log_repository.dart';

/// 약식 모드 출근/퇴근/휴게 버튼 로그 타입
enum SimpleModeAttendanceType {
  workIn, // 출근
  workOut, // 퇴근
  breakTime // 휴게 버튼
}

extension SimpleModeAttendanceTypeX on SimpleModeAttendanceType {
  /// SQLite에 저장되는 코드 값
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

  /// Firestore에 사용하는 상태 라벨 (CommuteLogRepository.status 용)
  String get statusLabel {
    switch (this) {
      case SimpleModeAttendanceType.workIn:
        return '출근';
      case SimpleModeAttendanceType.workOut:
        return '퇴근';
      case SimpleModeAttendanceType.breakTime:
        return '휴게';
    }
  }

  /// 출근/퇴근 여부 (로컬 SQLite 테이블 분리를 위한 헬퍼)
  bool get isWork {
    switch (this) {
      case SimpleModeAttendanceType.workIn:
      case SimpleModeAttendanceType.workOut:
        return true;
      case SimpleModeAttendanceType.breakTime:
        return false;
    }
  }

  /// 휴게 여부 (로컬 SQLite 테이블 분리를 위한 헬퍼)
  bool get isBreak => this == SimpleModeAttendanceType.breakTime;
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
  SimpleModeAttendanceRepository._({
    CommuteLogRepository? commuteLogRepository,
  }) : _commuteLogRepository = commuteLogRepository ?? CommuteLogRepository();

  static final SimpleModeAttendanceRepository instance = SimpleModeAttendanceRepository._();

  /// Firestore 로그용 레포지토리
  final CommuteLogRepository _commuteLogRepository;

  // 예: 2025-12-08
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');

  // 예: 09:00 (항상 두 자리 시각)
  final DateFormat _timeFormatter = DateFormat('HH:mm');

  static const String _breakTypeStart = 'start';

  /// 버튼을 누른 시각을 그대로 한 줄 INSERT (로컬 SQLite 전용)
  ///
  /// - v3/v4 스키마:
  ///   - 출근/퇴근: simple_work_attendance 테이블 사용
  ///   - 휴게: simple_break_attendance 테이블 사용
  ///   - 각각 PRIMARY KEY 제약으로 동일 날짜/타입은 항상 마지막 값만 유지
  ///
  /// ⚠️ Firestore에는 아무 것도 쓰지 않는 순수 로컬 메서드입니다.
  Future<void> insertEvent({
    required DateTime dateTime,
    required SimpleModeAttendanceType type,
  }) async {
    final db = await SimpleModeDb.instance.database;

    // 'yyyy-MM-dd'
    final date = _dateFormatter.format(dateTime);

    // 'HH:mm' → 9시도 09:00 형식으로 저장
    final time = _timeFormatter.format(dateTime);

    final createdAt = dateTime.toIso8601String();

    if (type.isWork) {
      // 출근/퇴근 → simple_work_attendance
      await db.insert(
        'simple_work_attendance',
        <String, Object?>{
          'date': date,
          'type': type.code, // 'work_in' / 'work_out'
          'time': time,
          'created_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else if (type.isBreak) {
      // 휴게 → simple_break_attendance
      await db.insert(
        'simple_break_attendance',
        <String, Object?>{
          'date': date,
          'type': _breakTypeStart, // 항상 "start" 로만 저장
          'time': time,
          'created_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 특정 날짜의 출근/휴게/퇴근 기록을 한 번에 조회 (로컬 SQLite)
  ///
  /// - 출근/퇴근: simple_work_attendance 에서 조회
  /// - 휴게: simple_break_attendance 에서 type="start" 한 건 조회
  ///
  /// 반환: { SimpleModeAttendanceType.workIn: '09:12', ... } 형식
  Future<Map<SimpleModeAttendanceType, String>> getEventsForDate(
    DateTime dateTime,
  ) async {
    final db = await SimpleModeDb.instance.database;

    final date = _dateFormatter.format(dateTime); // 'yyyy-MM-dd'

    final result = <SimpleModeAttendanceType, String>{};

    // 1) 출근/퇴근 테이블 조회
    final workRows = await db.query(
      'simple_work_attendance',
      columns: ['type', 'time'],
      where: 'date = ?',
      whereArgs: <Object?>[date],
    );

    for (final row in workRows) {
      final typeCode = row['type'] as String;
      final time = row['time'] as String;

      // nullable → non-null 변환
      final maybeType = simpleModeAttendanceTypeFromCode(typeCode);
      if (maybeType == null) {
        continue;
      }

      if (maybeType == SimpleModeAttendanceType.workIn || maybeType == SimpleModeAttendanceType.workOut) {
        result[maybeType] = time;
      }
    }

    // 2) 휴게 테이블 조회 (type = "start" 인 행만 사용)
    final breakRows = await db.query(
      'simple_break_attendance',
      columns: ['time'],
      where: 'date = ? AND type = ?',
      whereArgs: <Object?>[date, _breakTypeStart],
    );

    if (breakRows.isNotEmpty) {
      final time = breakRows.first['time'] as String;
      result[SimpleModeAttendanceType.breakTime] = time;
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ SQLite + Firestore를 동시에 업데이트하는 브리지 메서드
  // ─────────────────────────────────────────────────────────────

  /// 약식 모드 펀칭 1회에 대해:
  ///  1) 로컬 SQLite(출근/퇴근/휴게용 분리 테이블)에 저장
  ///  2) Firestore(commute_user_logs)에 동일한 시각으로 로그 적재
  ///
  /// - Firestore 쪽은 CommuteLogRepository를 사용
  /// - 이미 해당 날짜/상태에 로그가 있으면 Firestore에는 다시 쓰지 않음
  ///
  /// 사용 예:
  ///   await SimpleModeAttendanceRepository.instance.insertEventAndUpload(
  ///     dateTime: now,
  ///     type: SimpleModeAttendanceType.workIn,
  ///     userId: userId,
  ///     userName: userName,
  ///     area: area,
  ///     division: division,
  ///   );
  Future<void> insertEventAndUpload({
    required DateTime dateTime,
    required SimpleModeAttendanceType type,
    required String userId,
    required String userName,
    required String area,
    required String division,
  }) async {
    // 1) 항상 먼저 로컬 SQLite에 기록 (오프라인에서도 동작)
    await insertEvent(dateTime: dateTime, type: type);

    // 2) Firestore 에 쓸 공통 포맷
    final dateStr = _dateFormatter.format(dateTime); // "2025-12-09"
    final recordedTime = _timeFormatter.format(dateTime); // "09:30"
    final statusLabel = type.statusLabel; // "출근"/"휴게"/"퇴근"

    // 3) 해당 날짜에 이미 로그 있는지 확인
    final alreadyExists = await _commuteLogRepository.hasLogForDate(
      status: statusLabel,
      userId: userId,
      dateStr: dateStr,
    );

    if (alreadyExists) {
      // 이미 Firestore에 존재하면 추가 업로드는 생략
      return;
    }

    // 4) Firestore에 업로드
    //    (CommuteLogRepository 내부에서 예외는 swallow + DebugDatabaseLogger 기록)
    await _commuteLogRepository.addLog(
      status: statusLabel,
      userId: userId,
      userName: userName,
      area: area,
      division: division,
      dateStr: dateStr,
      recordedTime: recordedTime,
      dateTime: dateTime,
    );
  }

  /// (선택) 특정 날짜의 약식 모드 로컬 데이터를
  /// Firestore로 재동기화하는 유틸리티 메서드.
  ///
  /// - 오프라인 상태에서 쌓인 SQLite 로그를
  ///   나중에 한 번에 Firestore에 반영하는 용도로 사용 가능.
  ///
  /// 사용 예:
  ///   await SimpleModeAttendanceRepository.instance.syncDateToRemote(
  ///     date: DateTime(2025, 12, 9),
  ///     userId: userId,
  ///     userName: userName,
  ///     area: area,
  ///     division: division,
  ///   );
  Future<void> syncDateToRemote({
    required DateTime date,
    required String userId,
    required String userName,
    required String area,
    required String division,
  }) async {
    // 분리된 두 테이블(simple_work_attendance, simple_break_attendance)을
    // getEventsForDate 가 한 번에 조합해 주므로,
    // 기존 구현을 그대로 사용할 수 있음.
    final localEvents = await getEventsForDate(date);
    if (localEvents.isEmpty) return;

    for (final entry in localEvents.entries) {
      final type = entry.key;
      final timeStr = entry.value; // "HH:mm"

      final dateStr = _dateFormatter.format(date);
      final statusLabel = type.statusLabel;

      final alreadyExists = await _commuteLogRepository.hasLogForDate(
        status: statusLabel,
        userId: userId,
        dateStr: dateStr,
      );
      if (alreadyExists) {
        continue;
      }

      // timeStr 을 DateTime 의 시/분으로 합성해서 dateTime 생성 (초는 0으로 가정)
      final parts = timeStr.split(':');
      final hour = int.tryParse(parts.elementAt(0)) ?? 0;
      final minute = int.tryParse(parts.elementAt(1)) ?? 0;
      final dateTime = DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      );

      await _commuteLogRepository.addLog(
        status: statusLabel,
        userId: userId,
        userName: userName,
        area: area,
        division: division,
        dateStr: dateStr,
        recordedTime: timeStr,
        dateTime: dateTime,
      );
    }
  }
}
