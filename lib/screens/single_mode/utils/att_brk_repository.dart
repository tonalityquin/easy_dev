// lib/time_record/simple_mode/simple_mode_attendance_repository.dart
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'att_brk_mode_db.dart';
import '../../../../repositories/commute_repo_services/commute_log_repository.dart';

/// 약식 모드 출근/퇴근/휴게 버튼 로그 타입
enum AttBrkModeType {
  workIn, // 출근
  workOut, // 퇴근
  breakTime, // 휴게
}

extension AttBrkTypeX on AttBrkModeType {
  /// SQLite에 저장되는 코드 값
  String get code {
    switch (this) {
      case AttBrkModeType.workIn:
        return 'work_in';
      case AttBrkModeType.workOut:
        return 'work_out';
      case AttBrkModeType.breakTime:
        return 'break';
    }
  }

  /// Firestore(commute_user_logs) status 라벨
  String get statusLabel {
    switch (this) {
      case AttBrkModeType.workIn:
        return '출근';
      case AttBrkModeType.workOut:
        return '퇴근';
      case AttBrkModeType.breakTime:
        return '휴게';
    }
  }

  /// 출근/퇴근 여부 (로컬 SQLite 테이블 분리를 위한 헬퍼)
  bool get isWork {
    switch (this) {
      case AttBrkModeType.workIn:
      case AttBrkModeType.workOut:
        return true;
      case AttBrkModeType.breakTime:
        return false;
    }
  }

  /// 휴게 여부 (로컬 SQLite 테이블 분리를 위한 헬퍼)
  bool get isBreak => this == AttBrkModeType.breakTime;
}

/// DB에 저장된 type 문자열 → Enum 매핑
AttBrkModeType? singleModeAttBrkTypeFromCode(String code) {
  switch (code) {
    case 'work_in':
      return AttBrkModeType.workIn;
    case 'work_out':
      return AttBrkModeType.workOut;
    case 'break':
      return AttBrkModeType.breakTime;
  }
  return null;
}

/// 약식 모드 펀칭 로그(Local SQLite) + (선택) Firestore 업로드 브리지
class AttBrkRepository {
  AttBrkRepository._({
    CommuteLogRepository? commuteLogRepository,
  }) : _commuteLogRepository = commuteLogRepository ?? CommuteLogRepository();

  static final AttBrkRepository instance = AttBrkRepository._();

  /// Firestore 로그 레포지토리
  final CommuteLogRepository _commuteLogRepository;

  /// 예: 2025-12-08
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');

  /// 예: 09:00
  final DateFormat _timeFormatter = DateFormat('HH:mm');

  static const String _breakTypeStart = 'start';

  Future<Database> get _database async => AttBrkModeDb.instance.database;

  /// 버튼을 누른 시각을 로컬 SQLite에 저장
  ///
  /// - 출근/퇴근: simple_work_attendance
  /// - 휴게: simple_break_attendance (type="start" 고정)
  ///
  /// ConflictAlgorithm.replace로 동일 날짜/타입은 마지막 값만 유지
  ///
  /// ⚠️ 이 메서드는 로컬 전용(네트워크/Firestore 호출 없음)
  Future<void> insertEvent({
    required DateTime dateTime,
    required AttBrkModeType type,
  }) async {
    final db = await _database;

    final date = _dateFormatter.format(dateTime);
    final time = _timeFormatter.format(dateTime);
    final createdAt = dateTime.toIso8601String();

    if (type.isWork) {
      await db.insert(
        'simple_work_attendance',
        <String, Object?>{
          'date': date,
          'type': type.code,
          'time': time,
          'created_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else if (type.isBreak) {
      await db.insert(
        'simple_break_attendance',
        <String, Object?>{
          'date': date,
          'type': _breakTypeStart,
          'time': time,
          'created_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 특정 날짜의 출근/휴게/퇴근 기록 조회 (로컬 SQLite)
  ///
  /// 반환: { AttBrkModeType.workIn: '09:12', ... }
  Future<Map<AttBrkModeType, String>> getEventsForDate(DateTime dateTime) async {
    final db = await _database;
    final date = _dateFormatter.format(dateTime);

    final result = <AttBrkModeType, String>{};

    // 출근/퇴근
    final workRows = await db.query(
      'simple_work_attendance',
      columns: ['type', 'time'],
      where: 'date = ?',
      whereArgs: <Object?>[date],
    );

    for (final row in workRows) {
      final typeCode = row['type'] as String;
      final time = row['time'] as String;

      final maybeType = singleModeAttBrkTypeFromCode(typeCode);
      if (maybeType == null) continue;

      if (maybeType == AttBrkModeType.workIn || maybeType == AttBrkModeType.workOut) {
        result[maybeType] = time;
      }
    }

    // 휴게(type="start")
    final breakRows = await db.query(
      'simple_break_attendance',
      columns: ['time'],
      where: 'date = ? AND type = ?',
      whereArgs: <Object?>[date, _breakTypeStart],
    );

    if (breakRows.isNotEmpty) {
      final time = breakRows.first['time'] as String;
      result[AttBrkModeType.breakTime] = time;
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ SQLite + Firestore 동시 업데이트 브리지
  // ─────────────────────────────────────────────────────────────

  /// 1) 로컬 SQLite 저장
  /// 2) Firestore(commute_user_logs) 업로드(중복이면 스킵)
  ///
  /// ⚠️ Firestore 처리 실패는 CommuteLogRepository 내부 정책에 따라 로깅 후 무시될 수 있음.
  Future<void> insertEventAndUpload({
    required DateTime dateTime,
    required AttBrkModeType type,
    required String userId,
    required String userName,
    required String area,
    required String division,
  }) async {
    // 1) 로컬 먼저
    await insertEvent(dateTime: dateTime, type: type);

    final dateStr = _dateFormatter.format(dateTime);
    final recordedTime = _timeFormatter.format(dateTime);
    final statusLabel = type.statusLabel;

    // 2) 중복 체크
    final alreadyExists = await _commuteLogRepository.hasLogForDate(
      status: statusLabel,
      userId: userId,
      dateStr: dateStr,
    );

    if (alreadyExists) return;

    // 3) 업로드
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

  /// 특정 날짜의 로컬 데이터를 Firestore로 재동기화
  Future<void> syncDateToRemote({
    required DateTime date,
    required String userId,
    required String userName,
    required String area,
    required String division,
  }) async {
    final localEvents = await getEventsForDate(date);
    if (localEvents.isEmpty) return;

    final dateStr = _dateFormatter.format(date);

    for (final entry in localEvents.entries) {
      final type = entry.key;
      final timeStr = entry.value;
      final statusLabel = type.statusLabel;

      final alreadyExists = await _commuteLogRepository.hasLogForDate(
        status: statusLabel,
        userId: userId,
        dateStr: dateStr,
      );
      if (alreadyExists) continue;

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
