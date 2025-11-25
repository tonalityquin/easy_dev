// lib/time_record/work_time_repository.dart
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'time_record_db.dart';
import 'work_day_summary.dart';

/// 근무 시간 기록/조회용 저장소
///
/// - recordInterval(start, end, isForeground):
///     특정 구간을 받아 날짜별로 쪼개서 work_daily_summary 에 누적
/// - getDaySummary(date):
///     해당 날짜의 포그라운드/백그라운드 누적 시간 조회
/// - getRangeSummary(startDate, endDate):
///     날짜 범위 요약 리스트 조회
class WorkTimeRepository {
  WorkTimeRepository._internal();

  static final WorkTimeRepository instance = WorkTimeRepository._internal();

  /// 'YYYY-MM-DD' 형태로 포맷
  String _dateKey(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  /// [start, end) 구간을 받아서
  /// - 하루를 넘는다면 날짜별로 잘라서
  /// - 포그라운드/백그라운드 초를 일자별로 누적 저장
  Future<void> recordInterval({
    required DateTime start,
    required DateTime end,
    required bool isForeground,
  }) async {
    if (!end.isAfter(start)) return;

    try {
      final db = await TimeRecordDb.instance.database;
      DateTime cursor = start;

      while (cursor.isBefore(end)) {
        final dayStart = DateTime(cursor.year, cursor.month, cursor.day);
        final nextDayStart = dayStart.add(const Duration(days: 1));

        final segmentStart = cursor;
        final segmentEnd = end.isBefore(nextDayStart) ? end : nextDayStart;

        if (!segmentEnd.isAfter(segmentStart)) {
          // 이론상 없지만 방어 코드
          break;
        }

        final seconds = segmentEnd.difference(segmentStart).inSeconds;
        if (seconds > 0) {
          final dateStr = _dateKey(dayStart);
          await _addToDay(
            db: db,
            date: dateStr,
            fgDelta: isForeground ? seconds : 0,
            bgDelta: isForeground ? 0 : seconds,
          );
        }

        cursor = nextDayStart;
      }
    } catch (e, st) {
      debugPrint('[WorkTimeRepository] recordInterval error: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> _addToDay({
    required Database db,
    required String date,
    int fgDelta = 0,
    int bgDelta = 0,
  }) async {
    final nowIso = DateTime.now().toIso8601String();

    final rows = await db.query(
      'work_daily_summary',
      where: 'date = ?',
      whereArgs: [date],
      limit: 1,
    );

    if (rows.isEmpty) {
      // 신규 일자
      final fgTotalSecs = fgDelta;
      final bgTotalSecs = bgDelta;
      final fgParts = _splitSecondsToHms(fgTotalSecs);
      final bgParts = _splitSecondsToHms(bgTotalSecs);

      await db.insert(
        'work_daily_summary',
        {
          'date': date,
          'fg_secs': fgTotalSecs,
          'bg_secs': bgTotalSecs,
          'fg_h': fgParts[0],
          'fg_m': fgParts[1],
          'fg_s': fgParts[2],
          'bg_h': bgParts[0],
          'bg_m': bgParts[1],
          'bg_s': bgParts[2],
          'created_at': nowIso,
          'updated_at': nowIso,
        },
      );
    } else {
      // 기존 일자 → 초 누적 후 h/m/s 재계산
      final row = rows.first;
      final prevFgSecs = (row['fg_secs'] as int? ?? 0);
      final prevBgSecs = (row['bg_secs'] as int? ?? 0);

      final newFgSecs = prevFgSecs + fgDelta;
      final newBgSecs = prevBgSecs + bgDelta;

      final fgParts = _splitSecondsToHms(newFgSecs);
      final bgParts = _splitSecondsToHms(newBgSecs);

      await db.update(
        'work_daily_summary',
        {
          'fg_secs': newFgSecs,
          'bg_secs': newBgSecs,
          'fg_h': fgParts[0],
          'fg_m': fgParts[1],
          'fg_s': fgParts[2],
          'bg_h': bgParts[0],
          'bg_m': bgParts[1],
          'bg_s': bgParts[2],
          'updated_at': nowIso,
        },
        where: 'date = ?',
        whereArgs: [date],
      );
    }
  }

  /// 특정 날짜(로컬 기준)의 요약 조회
  Future<WorkDaySummary?> getDaySummary(DateTime date) async {
    final db = await TimeRecordDb.instance.database;
    final dateStr = _dateKey(date);

    final rows = await db.query(
      'work_daily_summary',
      where: 'date = ?',
      whereArgs: [dateStr],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return WorkDaySummary.fromMap(rows.first);
  }

  /// 날짜 범위(포함) 요약 리스트 조회
  ///
  /// 예: 한 주 / 한 달 통계 등에 사용
  Future<List<WorkDaySummary>> getRangeSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    if (to.isBefore(from)) return [];

    final db = await TimeRecordDb.instance.database;

    final fromKey = _dateKey(DateTime(from.year, from.month, from.day));
    final toKey = _dateKey(DateTime(to.year, to.month, to.day));

    final rows = await db.query(
      'work_daily_summary',
      where: 'date >= ? AND date <= ?',
      whereArgs: [fromKey, toKey],
      orderBy: 'date ASC',
    );

    return rows.map((e) => WorkDaySummary.fromMap(e)).toList();
  }

  /// 모든 기록 삭제 (디버그/테스트용)
  Future<void> clearAll() async {
    final db = await TimeRecordDb.instance.database;
    await db.delete('work_daily_summary');
  }
}

/// 초 → [시, 분, 초] 로 나누기
List<int> _splitSecondsToHms(int totalSeconds) {
  if (totalSeconds <= 0) return [0, 0, 0];
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return [h, m, s];
}
