import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../features/account/applications/user_state.dart';
import '../../features/commute/domain/repositories/commute_log_repository.dart';
import '../../features/dev/application/area_state.dart';
import '../../features/mode_single/application/att_brk_mode_db.dart';
import 'document_box_action.dart';
import 'document_box_prompt_sheet.dart';
import 'leader_document_inventory_repository.dart';
import 'document_item.dart';

Future<DocumentBoxAction?> openLeaderDocumentBox(BuildContext context) {
  return showPromptOverlayBottomSheet<DocumentBoxAction>(
    context: context,
    useRootNavigator: false,
    builder: (sheetContext) {
      final userState = sheetContext.watch<UserState>();
      final repo = LeaderDocumentInventoryRepository.instance;
      return PromptDocumentBoxSheet(
        title: '리더 서류함',
        description: '리더 전용 보고서와 기록 제출 양식을 확인합니다.',
        stream: repo.streamForUser(userState),
        actionFor: _documentActionFor,
      );
    },
  );
}

DocumentBoxAction? _documentActionFor(DocumentItem item) {
  switch (item.type) {
    case DocumentType.statementForm:
      if (item.id == 'template-commute-record') {
        return DocumentBoxAction.submitLeaderCommuteRecords;
      }
      if (item.id == 'template-resttime-record') {
        return DocumentBoxAction.submitLeaderRestTimeRecords;
      }
      return DocumentBoxAction.openUserStatementForm;
    case DocumentType.workEndReportForm:
      return DocumentBoxAction.openWorkEndReportForm;
    case DocumentType.workStartReportForm:
      return DocumentBoxAction.openWorkStartReportForm;
    case DocumentType.generic:
      if (item.id == 'template-annual-leave-application') {
        return DocumentBoxAction.openBackupForm;
      }
      return null;
  }
}

class LocalCommuteRecord {
  final String status;
  final DateTime dateTime;
  final String localTable;
  final String localDate;
  final String localType;

  LocalCommuteRecord({
    required this.status,
    required this.dateTime,
    required this.localTable,
    required this.localDate,
    required this.localType,
  });
}

Future<List<LocalCommuteRecord>> _loadLocalCommuteRecordsFromSqlite({
  required BuildContext context,
  required List<String> statuses,
  required String userId,
}) async {
  final db = await AttBrkModeDb.instance.database;
  final result = <LocalCommuteRecord>[];

  final dateTimeParser = DateFormat('yyyy-MM-dd HH:mm');

  final needWorkIn = statuses.contains('출근');
  final needWorkOut = statuses.contains('퇴근');

  if (needWorkIn || needWorkOut) {
    final workRows = await db.query(
      'simple_work_attendance',
      columns: ['date', 'type', 'time'],
      orderBy: 'date ASC, created_at ASC',
    );

    for (final row in workRows) {
      final typeCode = row['type'] as String;
      final dateStr = row['date'] as String;
      final timeStr = row['time'] as String;

      String? statusLabel;
      if (typeCode == 'work_in' && needWorkIn) {
        statusLabel = '출근';
      } else if (typeCode == 'work_out' && needWorkOut) {
        statusLabel = '퇴근';
      } else {
        continue;
      }

      try {
        final dt = dateTimeParser.parse('$dateStr $timeStr');
        result.add(
          LocalCommuteRecord(
            status: statusLabel,
            dateTime: dt,
            localTable: 'simple_work_attendance',
            localDate: dateStr,
            localType: typeCode,
          ),
        );
      } catch (_) {
        continue;
      }
    }
  }

  final needBreak = statuses.contains('휴게');
  if (needBreak) {
    final breakRows = await db.query(
      'simple_break_attendance',
      columns: ['date', 'type', 'time'],
      orderBy: 'date ASC, created_at ASC',
    );

    for (final row in breakRows) {
      final dateStr = row['date'] as String;
      final typeCode = (row['type'] as String?) ?? 'start';
      final timeStr = row['time'] as String;

      try {
        final dt = dateTimeParser.parse('$dateStr $timeStr');
        result.add(
          LocalCommuteRecord(
            status: '휴게',
            dateTime: dt,
            localTable: 'simple_break_attendance',
            localDate: dateStr,
            localType: typeCode,
          ),
        );
      } catch (_) {
        continue;
      }
    }
  }

  return result;
}

Future<int> _deleteLocalAttendanceRow(LocalCommuteRecord record) async {
  final db = await AttBrkModeDb.instance.database;
  return db.delete(
    record.localTable,
    where: 'date = ? AND type = ?',
    whereArgs: [record.localDate, record.localType],
  );
}

Future<void> submitLeaderCommuteRecordsFromSqlite(BuildContext context) async {
  final userState = context.read<UserState>();
  final areaState = context.read<AreaState>();

  final userId = (userState.session?.id ?? '').trim();
  final userName = userState.name.trim();
  final area = (userState.session?.selectedArea ?? '').trim();
  final division = areaState.currentDivision.trim();

  if (userId.isEmpty || userName.isEmpty || area.isEmpty || division.isEmpty) {
    return;
  }

  try {
    final records = await _loadLocalCommuteRecordsFromSqlite(
      context: context,
      statuses: const ['출근', '퇴근'],
      userId: userId,
    );

    if (records.isEmpty) {
      return;
    }

    final repo = CommuteLogRepository();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');

    for (final record in records) {
      final status = record.status;
      final eventDateTime = record.dateTime;

      final dateStr = dateFormatter.format(eventDateTime);
      final recordedTime = timeFormatter.format(eventDateTime);

      final alreadyExists = await repo.hasLogForDate(
        status: status,
        userId: userId,
        dateStr: dateStr,
      );

      if (alreadyExists) {
        continue;
      }

      await repo.addLog(
        status: status,
        userId: userId,
        userName: userName,
        area: area,
        division: division,
        dateStr: dateStr,
        recordedTime: recordedTime,
        dateTime: eventDateTime,
      );

      final nowExists = await repo.hasLogForDate(
        status: status,
        userId: userId,
        dateStr: dateStr,
      );

      if (nowExists) {
      } else {}
    }
  } catch (e, st) {
    debugPrint('❌ [LeaderDocumentBoxSheet] 출퇴근 기록 제출 중 오류: $e');
    debugPrint('stack: $st');
  }
}

Future<void> submitLeaderRestTimeRecordsFromSqlite(BuildContext context) async {
  final userState = context.read<UserState>();
  final areaState = context.read<AreaState>();

  final userId = (userState.session?.id ?? '').trim();
  final userName = userState.name.trim();
  final area = (userState.session?.selectedArea ?? '').trim();
  final division = areaState.currentDivision.trim();

  if (userId.isEmpty || userName.isEmpty || area.isEmpty || division.isEmpty) {
    return;
  }

  try {
    final records = await _loadLocalCommuteRecordsFromSqlite(
      context: context,
      statuses: const ['휴게'],
      userId: userId,
    );

    if (records.isEmpty) {
      return;
    }

    final repo = CommuteLogRepository();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');

    for (final record in records) {
      final eventDateTime = record.dateTime;
      final dateStr = dateFormatter.format(eventDateTime);
      final recordedTime = timeFormatter.format(eventDateTime);

      final alreadyExists = await repo.hasLogForDate(
        status: '휴게',
        userId: userId,
        dateStr: dateStr,
      );

      if (alreadyExists) {
        await _deleteLocalAttendanceRow(record);
        continue;
      }

      await repo.addLog(
        status: '휴게',
        userId: userId,
        userName: userName,
        area: area,
        division: division,
        dateStr: dateStr,
        recordedTime: recordedTime,
        dateTime: eventDateTime,
      );

      final nowExists = await repo.hasLogForDate(
        status: '휴게',
        userId: userId,
        dateStr: dateStr,
      );

      if (nowExists) {
        await _deleteLocalAttendanceRow(record);
      }
    }
  } catch (e, st) {
    debugPrint('❌ [LeaderDocumentBoxSheet] 휴게시간 기록 제출 중 오류: $e');
    debugPrint('stack: $st');
  }
}
