import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/utils/area_context_debug_trace.dart';
import '../../app/utils/block_dialog/break_duration_blocking_dialog.dart';
import '../../features/account/applications/user_state.dart';
import '../../features/commute/domain/repositories/commute_log_repository.dart';
import '../../features/dev/application/area_state.dart';
import '../../features/mode_single/application/att_brk_mode_db.dart';
import '../../features/mode_single/application/att_brk_repository.dart';
import 'attendance_submission_diagnostics.dart';
import 'attendance_submission_review_model.dart';

class AttendanceSubmissionReviewRepository {
  AttendanceSubmissionReviewRepository._();

  static final AttendanceSubmissionReviewRepository instance =
      AttendanceSubmissionReviewRepository._();

  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');
  final DateFormat _dateTimeParser = DateFormat('yyyy-MM-dd HH:mm');
  final DateFormat _timeFormatter = DateFormat('HH:mm');

  Future<AttendanceSubmissionReviewSnapshot> load(
    AttendanceSubmissionKind kind,
  ) async {
    final records = await _loadLocalRecords(kind);
    final today = _currentDay();
    final latestLocalDay = records.isEmpty
        ? null
        : records
            .map((record) => _dayOnly(record.dateTime))
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final cutoffDay = _submissionCutoff(today);
    final uploadTargets = records
        .where((record) => !_dayOnly(record.dateTime).isAfter(cutoffDay))
        .toList(growable: false);
    final grouped = <String, AttendanceReviewDay>{};

    for (final record in uploadTargets) {
      final key = _dateFormatter.format(record.dateTime);
      final current = grouped[key] ??
          AttendanceReviewDay(date: _dayOnly(record.dateTime));
      if (record.status == '출근') {
        grouped[key] = current.copyWith(
          workIn: _timeFormatter.format(record.dateTime),
        );
      } else if (record.status == '퇴근') {
        grouped[key] = current.copyWith(
          workOut: _timeFormatter.format(record.dateTime),
        );
      } else if (record.status == '휴게') {
        grouped[key] = current.copyWith(
          breakTime: _timeFormatter.format(record.dateTime),
        );
      }
    }

    final days = grouped.values.toList(growable: false)
      ..sort((a, b) => a.date.compareTo(b.date));
    final snapshot = AttendanceSubmissionReviewSnapshot(
      kind: kind,
      localRecords: List<AttendanceSubmissionRecord>.unmodifiable(records),
      uploadTargets:
          List<AttendanceSubmissionRecord>.unmodifiable(uploadTargets),
      days: List<AttendanceReviewDay>.unmodifiable(days),
      latestLocalDay: latestLocalDay,
      cutoffDay: cutoffDay,
    );
    AttendanceSubmissionDiagnostics.log(
      'repository',
      'loaded kind=${kind.name} local=${snapshot.localRecordCount} eligible=${snapshot.eligibleRecordCount} days=${snapshot.days.length} complete=${snapshot.completeDayCount} missing=${snapshot.missingDayCount} today=${_dateFormatter.format(today)} latestLocal=${latestLocalDay == null ? '-' : _dateFormatter.format(latestLocalDay)} cutoff=${_dateFormatter.format(cutoffDay)}',
    );
    return snapshot;
  }

  Future<void> saveDay({
    required AttendanceSubmissionKind kind,
    required DateTime date,
    String? workIn,
    String? workOut,
    String? breakTime,
  }) async {
    final repo = AttBrkRepository.instance;
    switch (kind) {
      case AttendanceSubmissionKind.commute:
        await _writeOptional(
          repo: repo,
          date: date,
          type: AttBrkModeType.workIn,
          value: workIn,
        );
        await _writeOptional(
          repo: repo,
          date: date,
          type: AttBrkModeType.workOut,
          value: workOut,
        );
        break;
      case AttendanceSubmissionKind.restTime:
        await _writeOptional(
          repo: repo,
          date: date,
          type: AttBrkModeType.breakTime,
          value: breakTime,
        );
        break;
    }
    AttendanceSubmissionDiagnostics.log(
      'repository',
      'day_saved kind=${kind.name} date=${_dateFormatter.format(date)} workIn=${workIn ?? '-'} workOut=${workOut ?? '-'} breakTime=${breakTime ?? '-'}',
    );
  }

  Future<void> deleteDay({
    required AttendanceSubmissionKind kind,
    required DateTime date,
  }) async {
    final repo = AttBrkRepository.instance;
    switch (kind) {
      case AttendanceSubmissionKind.commute:
        await repo.deleteReviewCommuteDate(date);
        break;
      case AttendanceSubmissionKind.restTime:
        await repo.deleteReviewEvent(
          date: date,
          type: AttBrkModeType.breakTime,
        );
        break;
    }
    AttendanceSubmissionDiagnostics.log(
      'repository',
      'day_deleted kind=${kind.name} date=${_dateFormatter.format(date)}',
    );
  }

  Future<AttendanceSubmissionResult> submit(
    BuildContext context,
    AttendanceSubmissionKind kind,
  ) async {
    final preflight = await load(kind);
    final preflightInvalid = _invalidDays(preflight);
    AttendanceSubmissionDiagnostics.log(
      'submit',
      'preflight kind=${kind.name} records=${preflight.eligibleRecordCount} invalid=${preflightInvalid.length} cutoff=${_dateFormatter.format(preflight.cutoffDay)} latestLocal=${preflight.latestLocalDay == null ? '-' : _dateFormatter.format(preflight.latestLocalDay!)}',
    );
    if (preflightInvalid.isNotEmpty) {
      return _validationBlockedResult(kind, preflightInvalid.length);
    }
    if (preflight.uploadTargets.isEmpty) {
      AttendanceSubmissionDiagnostics.log(
        'submit',
        'no_targets phase=preflight kind=${kind.name}',
      );
      return const AttendanceSubmissionResult(
        confirmed: true,
        successCount: 0,
        skippedCount: 0,
        failedCount: 0,
        deletedCount: 0,
        message: '제출할 기록이 없습니다.',
      );
    }
    if (!context.mounted) {
      return const AttendanceSubmissionResult.cancelled();
    }
    final preflightSignature = _snapshotSignature(preflight);

    final proceed = await showBreakDurationBlockingDialog(
      context,
      message: kind == AttendanceSubmissionKind.commute
          ? '검토한 출퇴근 기록을\n서버에 제출합니다.\n\n제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.'
          : '검토한 휴게시간 기록을\n서버에 제출합니다.\n\n제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
      duration: const Duration(seconds: 5),
    );
    AttendanceSubmissionDiagnostics.log(
      'submit',
      'confirmation kind=${kind.name} proceed=$proceed',
    );
    if (!proceed || !context.mounted) {
      return const AttendanceSubmissionResult.cancelled();
    }

    final snapshot = await load(kind);
    final finalInvalid = _invalidDays(snapshot);
    AttendanceSubmissionDiagnostics.log(
      'submit',
      'final_snapshot kind=${kind.name} records=${snapshot.eligibleRecordCount} invalid=${finalInvalid.length} cutoff=${_dateFormatter.format(snapshot.cutoffDay)} latestLocal=${snapshot.latestLocalDay == null ? '-' : _dateFormatter.format(snapshot.latestLocalDay!)}',
    );
    if (finalInvalid.isNotEmpty) {
      return _validationBlockedResult(kind, finalInvalid.length);
    }
    final finalSignature = _snapshotSignature(snapshot);
    if (preflightSignature != finalSignature) {
      AttendanceSubmissionDiagnostics.log(
        'submit',
        'snapshot_changed kind=${kind.name} preflight=$preflightSignature final=$finalSignature',
      );
      return const AttendanceSubmissionResult(
        confirmed: true,
        successCount: 0,
        skippedCount: 0,
        failedCount: 1,
        deletedCount: 0,
        message: '최종 확인 중 기록 또는 제출 가능 범위가 변경되었습니다. Review를 다시 확인해 주세요.',
      );
    }
    if (snapshot.uploadTargets.isEmpty) {
      AttendanceSubmissionDiagnostics.log(
        'submit',
        'no_targets phase=final kind=${kind.name}',
      );
      return const AttendanceSubmissionResult(
        confirmed: true,
        successCount: 0,
        skippedCount: 0,
        failedCount: 0,
        deletedCount: 0,
        message: '최종 확인 중 제출할 기록이 없어졌습니다.',
      );
    }

    final userState = context.read<UserState>();
    final areaState = context.read<AreaState>();
    final userId = (userState.session?.id ?? '').trim();
    final userName = userState.name.trim();
    final selectedArea = (userState.session?.selectedArea ?? '').trim();
    final area = userState.currentArea.trim();
    final division = areaState.currentDivision.trim();
    final debugTag = kind == AttendanceSubmissionKind.commute
        ? 'AttendanceReview/CommuteSubmit'
        : 'AttendanceReview/BreakSubmit';

    AreaContextDebugTrace.record(
      debugTag,
      'attendance_upload_started',
      fields: <String, Object?>{
        'selectedArea': selectedArea,
        'currentArea': area,
        'currentDivision': division,
        'statuses': kind.statuses.join(','),
        'cutoff': _dateFormatter.format(snapshot.cutoffDay),
        'latestLocal': snapshot.latestLocalDay == null
            ? '-'
            : _dateFormatter.format(snapshot.latestLocalDay!),
      },
    );

    if (userId.isEmpty || userName.isEmpty || area.isEmpty || division.isEmpty) {
      final message = '${kind.shortLabel} 기록 제출 실패: 사용자/근무지 정보가 비어 있습니다.';
      AttendanceSubmissionDiagnostics.log(
        'submit',
        'context_invalid kind=${kind.name} userId=${userId.isNotEmpty} userName=${userName.isNotEmpty} area=${area.isNotEmpty} division=${division.isNotEmpty}',
      );
      return AttendanceSubmissionResult(
        confirmed: true,
        successCount: 0,
        skippedCount: 0,
        failedCount: snapshot.uploadTargets.length,
        deletedCount: 0,
        message: message,
      );
    }

    final remote = CommuteLogRepository();
    var successCount = 0;
    var skippedCount = 0;
    var failedCount = 0;
    var deletedCount = 0;

    try {
      for (final record in snapshot.uploadTargets) {
        final status = record.status;
        final eventDateTime = record.dateTime;
        final dateStr = _dateFormatter.format(eventDateTime);
        final recordedTime = _timeFormatter.format(eventDateTime);
        final alreadyExists = await remote.hasLogForDate(
          status: status,
          userId: userId,
          dateStr: dateStr,
        );
        if (alreadyExists) {
          skippedCount++;
          deletedCount += await _deleteLocalRecord(record);
          continue;
        }
        await remote.addLog(
          status: status,
          userId: userId,
          userName: userName,
          area: area,
          division: division,
          dateStr: dateStr,
          recordedTime: recordedTime,
          dateTime: eventDateTime,
        );
        final nowExists = await remote.hasLogForDate(
          status: status,
          userId: userId,
          dateStr: dateStr,
        );
        if (nowExists) {
          successCount++;
          deletedCount += await _deleteLocalRecord(record);
        } else {
          failedCount++;
        }
      }
      AttendanceSubmissionDiagnostics.log(
        'submit',
        'complete kind=${kind.name} success=$successCount skipped=$skippedCount failed=$failedCount deleted=$deletedCount cutoff=${_dateFormatter.format(snapshot.cutoffDay)} latestLocal=${snapshot.latestLocalDay == null ? '-' : _dateFormatter.format(snapshot.latestLocalDay!)}',
      );
      AreaContextDebugTrace.record(
        debugTag,
        'attendance_upload_completed',
        fields: <String, Object?>{
          'selectedArea': selectedArea,
          'currentArea': area,
          'success': successCount,
          'skipped': skippedCount,
          'failed': failedCount,
        },
      );
      return AttendanceSubmissionResult(
        confirmed: true,
        successCount: successCount,
        skippedCount: skippedCount,
        failedCount: failedCount,
        deletedCount: deletedCount,
        message: failedCount == 0
            ? '${kind.shortLabel} 기록 제출 완료: $successCount건 업로드, 중복 $skippedCount건'
            : '${kind.shortLabel} 기록 제출 결과: $successCount건 업로드, $failedCount건 실패',
      );
    } catch (error, stackTrace) {
      AttendanceSubmissionDiagnostics.log(
        'submit',
        'failure kind=${kind.name} error=$error stack=$stackTrace',
      );
      AreaContextDebugTrace.record(
        debugTag,
        'attendance_upload_failed',
        fields: <String, Object?>{
          'selectedArea': selectedArea,
          'currentArea': area,
          'error': '$error',
        },
      );
      return AttendanceSubmissionResult(
        confirmed: true,
        successCount: successCount,
        skippedCount: skippedCount,
        failedCount: failedCount + 1,
        deletedCount: deletedCount,
        message: '기록 제출 중 오류가 발생했습니다.',
      );
    }
  }

  String _snapshotSignature(AttendanceSubmissionReviewSnapshot snapshot) {
    final records = snapshot.uploadTargets
        .map(
          (record) =>
              '${record.localTable}|${record.localDate}|${record.localType}|${record.dateTime.toIso8601String()}',
        )
        .toList(growable: false)
      ..sort();
    return '${_dateFormatter.format(snapshot.cutoffDay)}::${records.join(';;')}';
  }

  List<AttendanceReviewDay> _invalidDays(
    AttendanceSubmissionReviewSnapshot snapshot,
  ) {
    return snapshot.days
        .where(
          (day) =>
              day.stateFor(snapshot.kind) != AttendanceReviewDayState.complete,
        )
        .toList(growable: false);
  }

  AttendanceSubmissionResult _validationBlockedResult(
    AttendanceSubmissionKind kind,
    int invalidCount,
  ) {
    final message = kind == AttendanceSubmissionKind.commute
        ? '출근 또는 퇴근 시간이 누락된 날짜를 먼저 수정해 주세요.'
        : '휴게시간이 비어 있는 날짜를 먼저 수정해 주세요.';
    AttendanceSubmissionDiagnostics.log(
      'submit',
      'validation_blocked kind=${kind.name} invalid=$invalidCount',
    );
    return AttendanceSubmissionResult(
      confirmed: true,
      successCount: 0,
      skippedCount: 0,
      failedCount: invalidCount,
      deletedCount: 0,
      message: message,
    );
  }

  Future<void> _writeOptional({
    required AttBrkRepository repo,
    required DateTime date,
    required AttBrkModeType type,
    required String? value,
  }) async {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      await repo.deleteReviewEvent(date: date, type: type);
      return;
    }
    await repo.upsertReviewEvent(
      date: date,
      type: type,
      time: normalized,
    );
  }

  Future<int> _deleteLocalRecord(AttendanceSubmissionRecord record) async {
    final db = await AttBrkModeDb.instance.database;
    return db.delete(
      record.localTable,
      where: 'date = ? AND type = ?',
      whereArgs: <Object?>[record.localDate, record.localType],
    );
  }

  Future<List<AttendanceSubmissionRecord>> _loadLocalRecords(
    AttendanceSubmissionKind kind,
  ) async {
    final db = await AttBrkModeDb.instance.database;
    final result = <AttendanceSubmissionRecord>[];
    if (kind == AttendanceSubmissionKind.commute) {
      final rows = await db.query(
        AttBrkModeDb.workAttendanceTable,
        columns: const <String>['date', 'type', 'time'],
        orderBy: 'date ASC, created_at ASC',
      );
      for (final row in rows) {
        final type = (row['type'] ?? '').toString();
        final date = (row['date'] ?? '').toString();
        final time = (row['time'] ?? '').toString();
        final status = type == 'work_in'
            ? '출근'
            : type == 'work_out'
                ? '퇴근'
                : null;
        if (status == null || date.isEmpty || time.isEmpty) continue;
        try {
          result.add(
            AttendanceSubmissionRecord(
              status: status,
              dateTime: _dateTimeParser.parse('$date $time'),
              localTable: AttBrkModeDb.workAttendanceTable,
              localDate: date,
              localType: type,
            ),
          );
        } catch (_) {}
      }
    } else {
      final rows = await db.query(
        AttBrkModeDb.breakAttendanceTable,
        columns: const <String>['date', 'type', 'time'],
        orderBy: 'date ASC, created_at ASC',
      );
      for (final row in rows) {
        final date = (row['date'] ?? '').toString();
        final type = (row['type'] ?? 'start').toString();
        final time = (row['time'] ?? '').toString();
        if (date.isEmpty || time.isEmpty) continue;
        try {
          result.add(
            AttendanceSubmissionRecord(
              status: '휴게',
              dateTime: _dateTimeParser.parse('$date $time'),
              localTable: AttBrkModeDb.breakAttendanceTable,
              localDate: date,
              localType: type,
            ),
          );
        } catch (_) {}
      }
    }
    return result;
  }

  DateTime _currentDay() => _dayOnly(DateTime.now());

  DateTime _submissionCutoff(DateTime today) =>
      today.subtract(const Duration(days: 1));

  DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
