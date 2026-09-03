import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../../app/utils/block_dialog/break_duration_blocking_dialog.dart';
import '../../../../../app/utils/status_dialog.dart';
import '../../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../shared/document/backup/backup_form_page.dart';
import '../../../../../shared/document/user_statement/user_statement_form_page.dart';
import '../../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../../account/applications/user_state.dart';
import '../../../../commute/domain/repositories/commute_log_repository.dart';
import '../../../../dev/application/area_state.dart';
import '../../../../selector/application/dev_auth.dart';
import '../../../application/att_brk_mode_db.dart';
import 'widgets/single_document_inventory_repository.dart';
import 'widgets/single_document_item.dart';

class _SingleDocumentBoxDiagnostics {
  static const int _limit = 120;
  static final List<String> _lines = <String>[];

  static void log(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final line =
        '[SingleDocumentBox][${DateTime.now().toIso8601String()}] $normalized';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[SingleDocumentBox] 기록된 로그가 없습니다.')});';
    }
    return _lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
  }

  static Future<void> showStatus(BuildContext context) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    log('developer_status_open');
    await StatusDialog.showSuccess(
      context,
      title: '서류함 상태',
      description: '서류함 Side Dock의 debugPrint 코드를 복사할 수 있습니다.',
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}

Future<void> openSingleDocumentBox(BuildContext context) async {
  _SingleDocumentBoxDiagnostics.log('route_push');
  await showOperationsRightSideDock<void>(
    context: context,
    useRootNavigator: false,
    barrierLabel: '서류함',
    maxWidth: 360,
    widthFactor: .92,
    barrierDismissible: true,
    builder: (_) => const _SingleDocumentBoxDock(),
  );
  _SingleDocumentBoxDiagnostics.log('route_closed');
}

Future<void> _closeSingleDocumentBoxAndOpen(
  BuildContext context,
  Future<void> Function(BuildContext rootContext) action,
) async {
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final rootContext = rootNavigator.context;
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
  }
  await action(rootContext);
}

class _SingleDocumentBoxDock extends StatelessWidget {
  const _SingleDocumentBoxDock();

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final userState = context.watch<UserState>();
    final repo = SingleDocumentInventoryRepository.instance;

    return CommonSideDockFrame(
      title: '서류함',
      subtitle: 'Single',
      icon: Icons.folder_open_rounded,
      onClose: () => Navigator.of(context).pop(),
      onLongPress: () => _SingleDocumentBoxDiagnostics.showStatus(context),
      headerAction: ValueListenableBuilder<bool>(
        valueListenable: DevAuth.devModeEnabled,
        builder: (context, enabled, _) {
          if (!enabled) return const SizedBox.shrink();
          return IconButton(
            tooltip: '상태 확인',
            onPressed: () => _SingleDocumentBoxDiagnostics.showStatus(context),
            icon: const Icon(Icons.bug_report_rounded),
          );
        },
      ),
      child: OpsDockListSurface(
        child: StreamBuilder<List<SingleDocumentItem>>(
          stream: repo.streamForUser(userState),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(color: tokens.accent),
              );
            }

            final items = snapshot.data ?? const <SingleDocumentItem>[];
            _SingleDocumentBoxDiagnostics.log(
              'inventory state=${snapshot.connectionState.name} count=${items.length}',
            );
            if (items.isEmpty) {
              return const _EmptyState();
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                color: tokens.borderSubtle,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return _DocumentListItem(
                  item: item,
                  onTap: () async {
                    _SingleDocumentBoxDiagnostics.log(
                      'item_tap id=${item.id} type=${item.type.name}',
                    );
                    switch (item.type) {
                      case SingleDocumentType.statementForm:
                        if (item.id == 'template-commute-record') {
                          final proceed = await showBreakDurationBlockingDialog(
                            context,
                            message:
                                '단말기에 저장된 출퇴근 기록을\n서버에 제출합니다.\n\n제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
                            duration: const Duration(seconds: 5),
                          );
                          if (!proceed) return;
                          await _submitCommuteRecordsFromSqlite(context);
                        } else if (item.id == 'template-resttime-record') {
                          final proceed = await showBreakDurationBlockingDialog(
                            context,
                            message:
                                '단말기에 저장된 휴게시간 기록을\n서버에 제출합니다.\n\n제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
                            duration: const Duration(seconds: 5),
                          );
                          if (!proceed) return;
                          await _submitRestTimeRecordsFromSqlite(context);
                        } else {
                          await _closeSingleDocumentBoxAndOpen(
                            context,
                            (rootContext) => showUserStatementSideDock(
                              context: rootContext,
                            ),
                          );
                        }
                        break;
                      case SingleDocumentType.handoverForm:
                        debugPrint(
                          '[SingleDocumentBox] handover_form_unavailable id=${item.id}',
                        );
                        break;
                      case SingleDocumentType.workEndReportForm:
                        debugPrint(
                          '[SingleDocumentBox] work_end_report_unavailable id=${item.id}',
                        );
                        break;
                      case SingleDocumentType.workStartReportForm:
                        debugPrint(
                          '[SingleDocumentBox] work_start_report_unavailable id=${item.id}',
                        );
                        break;
                      case SingleDocumentType.generic:
                        if (item.id == 'template-annual-leave-application') {
                          await _closeSingleDocumentBoxAndOpen(
                            context,
                            (rootContext) => showBackupApplicationSideDock(
                              context: rootContext,
                            ),
                          );
                        }
                        break;
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _DocumentListItem extends StatefulWidget {
  const _DocumentListItem({
    required this.item,
    required this.onTap,
  });

  final SingleDocumentItem item;
  final VoidCallback onTap;

  @override
  State<_DocumentListItem> createState() => _DocumentListItemState();
}

class _DocumentListItemState extends State<_DocumentListItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final cs = Theme.of(context).colorScheme;
    final accentColor = _accentColorForItem(context, widget.item);
    final typeLabel = _typeLabelForItem(widget.item);
    final iconData = _iconForItem(widget.item);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      button: true,
      label: widget.item.title,
      child: AnimatedScale(
        scale: _pressed ? .985 : 1,
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (!mounted || _pressed == value) return;
              setState(() => _pressed = value);
            },
            child: AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              color: _pressed
                  ? tokens.surfaceSelected.withOpacity(.6)
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    curve: CommonUiMotion.standard,
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(iconData, color: accentColor, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              typeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: accentColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: tokens.iconSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 90,
                  height: 64,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                Icon(
                  Icons.folder_open,
                  size: 40,
                  color: cs.onSurfaceVariant.withOpacity(0.85),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '표시할 서류가 없어요',
              style: textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '필요한 서류 양식이 생성되면\n이 문서철에 차곡차곡 꽂혀요.',
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
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

DateTime _dayOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

class _FilteredLocalRecords {
  final List<LocalCommuteRecord> uploadTargets;
  final DateTime latestDay;
  final DateTime cutoffDay;

  const _FilteredLocalRecords({
    required this.uploadTargets,
    required this.latestDay,
    required this.cutoffDay,
  });
}

_FilteredLocalRecords _filterUpToDayBeforeLatest(
    List<LocalCommuteRecord> records) {
  if (records.isEmpty) {
    return _FilteredLocalRecords(
      uploadTargets: const <LocalCommuteRecord>[],
      latestDay: DateTime(1970, 1, 1),
      cutoffDay: DateTime(1970, 1, 1),
    );
  }

  final latestDay = records
      .map((r) => _dayOnly(r.dateTime))
      .reduce((a, b) => a.isAfter(b) ? a : b);

  final cutoffDay = latestDay.subtract(const Duration(days: 1));

  final targets =
      records.where((r) => !_dayOnly(r.dateTime).isAfter(cutoffDay)).toList();

  return _FilteredLocalRecords(
    uploadTargets: targets,
    latestDay: latestDay,
    cutoffDay: cutoffDay,
  );
}

Future<List<LocalCommuteRecord>> _loadLocalCommuteRecordsFromSqlite({
  required List<String> statuses,
}) async {
  final db = await AttBrkModeDb.instance.database;
  final result = <LocalCommuteRecord>[];

  final dateTimeParser = DateFormat('yyyy-MM-dd HH:mm');

  final needWorkIn = statuses.contains('출근');
  final needWorkOut = statuses.contains('퇴근');

  if (needWorkIn || needWorkOut) {
    final workRows = await db.query(
      AttBrkModeDb.workAttendanceTable,
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
            localTable: AttBrkModeDb.workAttendanceTable,
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
      AttBrkModeDb.breakAttendanceTable,
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
            localTable: AttBrkModeDb.breakAttendanceTable,
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

Future<void> _submitLocalAttendanceRecordsToFirestore(
  BuildContext context, {
  required List<String> statuses,
  required String validationFailMessage,
  required String noLocalRecordsMessage,
  required String noUploadTargetsMessage,
  required String resultPrefix,
  required String debugTag,
}) async {
  final userState = context.read<UserState>();
  final areaState = context.read<AreaState>();

  final userId = (userState.session?.id ?? '').trim();
  final userName = userState.name.trim();
  final area = (userState.session?.selectedArea ?? '').trim();
  final division = areaState.currentDivision.trim();

  if (userId.isEmpty || userName.isEmpty || area.isEmpty || division.isEmpty) {
    debugPrint(validationFailMessage);
    return;
  }

  try {
    final records = await _loadLocalCommuteRecordsFromSqlite(
      statuses: statuses,
    );

    if (records.isEmpty) {
      debugPrint(noLocalRecordsMessage);
      return;
    }

    final filtered = _filterUpToDayBeforeLatest(records);
    final uploadTargets = filtered.uploadTargets;

    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');

    final latestDayStr = dateFormatter.format(filtered.latestDay);
    final cutoffDayStr = dateFormatter.format(filtered.cutoffDay);

    if (uploadTargets.isEmpty) {
      debugPrint(
        '$noUploadTargetsMessage\n'
        '가장 최근 날짜: $latestDayStr\n'
        '업로드 범위: $cutoffDayStr(포함) 이전',
      );
      return;
    }

    final repo = CommuteLogRepository();

    var successCount = 0;
    var skippedCount = 0;
    var failedCount = 0;
    var deletedCount = 0;

    for (final record in uploadTargets) {
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
        skippedCount++;
        deletedCount += await _deleteLocalAttendanceRow(record);
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
        successCount++;
        deletedCount += await _deleteLocalAttendanceRow(record);
      } else {
        failedCount++;
      }
    }

    debugPrint(
      '$resultPrefix: '
      '$successCount건 업로드, '
      '중복 $skippedCount건, '
      '실패 $failedCount건, '
      '로컬 삭제 $deletedCount건.\n'
      '(최신일 $latestDayStr 제외, $cutoffDayStr까지 업로드)',
    );
  } catch (e, st) {
    debugPrint('❌ [$debugTag] 제출 중 오류: $e');
    debugPrint('stack: $st');
    debugPrint(
      '기록 제출 중 오류가 발생했습니다.\n'
      '네트워크 또는 Firebase 설정을 확인해 주세요.',
    );
  }
}

Future<void> _submitCommuteRecordsFromSqlite(BuildContext context) async {
  return _submitLocalAttendanceRecordsToFirestore(
    context,
    statuses: const ['출근', '퇴근'],
    validationFailMessage: '출퇴근 기록 제출 실패: 사용자/근무지 정보가 비어 있습니다.\n'
        '관리자에게 계정 및 근무지 설정을 확인해 달라고 요청해 주세요.',
    noLocalRecordsMessage: '제출할 출퇴근 기록이 없습니다.',
    noUploadTargetsMessage: '업로드할 출퇴근 기록이 없습니다. (가장 최근 날짜 기록은 제외합니다.)',
    resultPrefix: '출퇴근 기록 제출 완료',
    debugTag: 'SingleDocumentBoxSheet/CommuteSubmit',
  );
}

Future<void> _submitRestTimeRecordsFromSqlite(BuildContext context) async {
  return _submitLocalAttendanceRecordsToFirestore(
    context,
    statuses: const ['휴게'],
    validationFailMessage: '휴게시간 기록 제출 실패: 사용자/근무지 정보가 비어 있습니다.\n'
        '관리자에게 계정 및 근무지 설정을 확인해 달라고 요청해 주세요.',
    noLocalRecordsMessage: '제출할 휴게시간 기록이 없습니다.',
    noUploadTargetsMessage: '업로드할 휴게시간 기록이 없습니다. (가장 최근 날짜 기록은 제외합니다.)',
    resultPrefix: '휴게시간 기록 제출 완료',
    debugTag: 'SingleDocumentBoxSheet/BreakSubmit',
  );
}

Color _accentColorForItem(BuildContext context, SingleDocumentItem item) {
  final cs = Theme.of(context).colorScheme;

  if (item.type == SingleDocumentType.statementForm) {
    switch (item.id) {
      case 'template-statement':
        return cs.primary;
      case 'template-commute-record':
        return cs.secondary;
      case 'template-resttime-record':
        return cs.tertiary;
    }
    return cs.primary;
  }

  if (item.type == SingleDocumentType.generic) {
    if (item.id == 'template-annual-leave-application') {
      return cs.outline;
    }
    return cs.outline;
  }

  return cs.outline;
}

IconData _iconForItem(SingleDocumentItem item) {
  if (item.type == SingleDocumentType.statementForm) {
    switch (item.id) {
      case 'template-commute-record':
        return Icons.access_time;
      case 'template-resttime-record':
        return Icons.coffee_outlined;
      case 'template-statement':
      default:
        return Icons.description_outlined;
    }
  }

  if (item.type == SingleDocumentType.generic) {
    return Icons.insert_drive_file_outlined;
  }

  return Icons.insert_drive_file_outlined;
}

String _typeLabelForItem(SingleDocumentItem item) {
  if (item.type == SingleDocumentType.statementForm) {
    switch (item.id) {
      case 'template-statement':
        return '경위서';
      case 'template-commute-record':
        return '출퇴근 기록';
      case 'template-resttime-record':
        return '휴게시간 기록';
    }
  }

  if (item.type == SingleDocumentType.generic) {
    return '기타 문서';
  }

  return '기타 문서';
}
