import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../features/account/applications/user_state.dart';
import '../../../features/commute/domain/repositories/commute_log_repository.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/mode_single/application/att_brk_mode_db.dart';
import 'document_box_action.dart';
import 'fielder_document_inventory_repository.dart';
import 'document_item.dart';

Future<DocumentBoxAction?> openFielderDocumentBox(BuildContext context) async {
  return showModalBottomSheet<DocumentBoxAction>(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _FielderDocumentBoxSheet(),
  );
}

class _FielderDocumentBoxSheet extends StatelessWidget {
  const _FielderDocumentBoxSheet();

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final repo = FielderDocumentInventoryRepository.instance;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, scrollController) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            children: [
              const _SheetHandle(),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5EB),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const _BinderSpine(),
                      const VerticalDivider(
                        width: 0,
                        thickness: 0.6,
                        color: Color(0xFFE0D7C5),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const _SheetHeader(),
                            const Divider(
                              height: 1,
                              thickness: 0.8,
                              color: Color(0xFFE5DFD0),
                            ),
                            Expanded(
                              child: StreamBuilder<List<DocumentItem>>(
                                stream: repo.streamForUser(userState),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }

                                  final items =
                                      snapshot.data ?? const <DocumentItem>[];

                                  if (items.isEmpty) {
                                    return const _EmptyState();
                                  }

                                  return ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return _DocumentListItem(
                                        item: item,
                                        onTap: () {
                                          switch (item.type) {
                                            case DocumentType.statementForm:
                                              if (item.id ==
                                                  'template-commute-record') {
                                                Navigator.of(context).pop(
                                                  DocumentBoxAction
                                                      .submitFielderCommuteRecords,
                                                );
                                              } else if (item.id ==
                                                  'template-resttime-record') {
                                                Navigator.of(context).pop(
                                                  DocumentBoxAction
                                                      .submitFielderRestTimeRecords,
                                                );
                                              } else {
                                                Navigator.of(context).pop(
                                                  DocumentBoxAction
                                                      .openUserStatementForm,
                                                );
                                              }
                                              break;
                                            case DocumentType.workEndReportForm:
                                              Navigator.of(context).pop(
                                                DocumentBoxAction
                                                    .openWorkEndReportForm,
                                              );
                                              break;
                                            case DocumentType
                                                  .workStartReportForm:
                                              Navigator.of(context).pop(
                                                DocumentBoxAction
                                                    .openWorkStartReportForm,
                                              );
                                              break;
                                            case DocumentType.generic:
                                              if (item.id ==
                                                  'template-annual-leave-application') {
                                                Navigator.of(context).pop(
                                                  DocumentBoxAction
                                                      .openBackupForm,
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 6,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.brown.withOpacity(0.25),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _BinderSpine extends StatelessWidget {
  const _BinderSpine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      decoration: const BoxDecoration(
        color: Color(0xFFE0D7C5),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          5,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.brown[200],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
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

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.brown.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.folder_special_outlined,
              size: 22,
              color: Colors.brown,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '내 문서철',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4A3A28),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '보고서와 인수인계, 경위서 양식을 모아두었어요.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A7A65),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '닫기',
            icon: const Icon(
              Icons.close,
              size: 20,
              color: Color(0xFF7A6A55),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _DocumentListItem extends StatelessWidget {
  final DocumentItem item;
  final VoidCallback onTap;

  const _DocumentListItem({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColorForItem(item);
    final typeLabel = _typeLabelForItem(item);
    final iconData = _iconForType(item.type);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 80,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: accentColor.withOpacity(0.15),
                        child: Icon(
                          iconData,
                          color: accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF3C342A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _buildSubtitle(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF7A6F63),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
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
                                      color: accentColor.darken(0.1),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: Color(0xFF9A8C7A),
                ),
              ),
            ],
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
                    color: const Color(0xFFEDE5D4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const Icon(
                  Icons.folder_open,
                  size: 40,
                  color: Color(0xFFB09A7A),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '표시할 서류가 없어요',
              style: textTheme.titleMedium?.copyWith(
                color: const Color(0xFF4A3A28),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '필요한 서류 양식이 생성되면\n이 문서철에 차곡차곡 꽂혀요.',
              style: textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF8A7A65),
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

Future<void> _submitLocalAttendanceRecordsToFirestore(
  BuildContext context, {
  required List<String> statuses,
  required String debugTag,
}) async {
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
      statuses: statuses,
    );

    if (records.isEmpty) {
      return;
    }

    final filtered = _filterUpToDayBeforeLatest(records);
    final uploadTargets = filtered.uploadTargets;

    if (uploadTargets.isEmpty) {
      return;
    }

    final repo = CommuteLogRepository();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');

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
        await _deleteLocalAttendanceRow(record);
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
        await _deleteLocalAttendanceRow(record);
      }
    }
  } catch (e, st) {
    debugPrint('❌ [$debugTag] 기록 제출 중 오류: $e');
    debugPrint('stack: $st');
  }
}

Future<void> submitFielderCommuteRecordsFromSqlite(BuildContext context) async {
  return _submitLocalAttendanceRecordsToFirestore(
    context,
    statuses: const ['출근', '퇴근'],
    debugTag: 'FielderDocumentBoxSheet/CommuteSubmit',
  );
}

Future<void> submitFielderRestTimeRecordsFromSqlite(
    BuildContext context) async {
  return _submitLocalAttendanceRecordsToFirestore(
    context,
    statuses: const ['휴게'],
    debugTag: 'FielderDocumentBoxSheet/BreakSubmit',
  );
}

String _buildSubtitle(DocumentItem item) {
  final parts = <String>[];
  if (item.subtitle != null && item.subtitle!.isNotEmpty) {
    parts.add(item.subtitle!);
  }
  parts.add('수정: ${_formatDateTime(item.updatedAt)}');
  return parts.join(' • ');
}

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}

Color _accentColorForType(DocumentType type) {
  switch (type) {
    case DocumentType.workStartReportForm:
      return const Color(0xFF4F9A94);
    case DocumentType.workEndReportForm:
      return const Color(0xFFEF6C53);
    case DocumentType.statementForm:
      return const Color(0xFF5C6BC0);
    case DocumentType.generic:
      return const Color(0xFF757575);
  }
}

Color _accentColorForItem(DocumentItem item) {
  if (item.type == DocumentType.workEndReportForm) {
    if (item.id == 'template-work-end-report') {
      return const Color(0xFFEF6C53);
    }
    if (item.id == 'template-end-work-report') {
      return const Color(0xFFD84315);
    }
  }
  return _accentColorForType(item.type);
}

IconData _iconForType(DocumentType type) {
  switch (type) {
    case DocumentType.workStartReportForm:
      return Icons.wb_sunny_outlined;
    case DocumentType.workEndReportForm:
      return Icons.nights_stay_outlined;
    case DocumentType.statementForm:
      return Icons.description_outlined;
    case DocumentType.generic:
      return Icons.insert_drive_file_outlined;
  }
}

String _typeLabelForItem(DocumentItem item) {
  if (item.type == DocumentType.workEndReportForm) {
    if (item.id == 'template-work-end-report') {
      return '퇴근 보고';
    }
    if (item.id == 'template-end-work-report') {
      return '업무 종료 보고';
    }
  }

  if (item.type == DocumentType.statementForm) {
    switch (item.id) {
      case 'template-commute-record':
        return '출퇴근 기록';
      case 'template-resttime-record':
        return '휴게시간 기록';
    }
  }

  return _typeLabelForType(item.type);
}

String _typeLabelForType(DocumentType type) {
  switch (type) {
    case DocumentType.workStartReportForm:
      return '업무 시작 보고';
    case DocumentType.workEndReportForm:
      return '퇴근/업무 종료';
    case DocumentType.statementForm:
      return '경위서';
    case DocumentType.generic:
      return '기타 문서';
  }
}

extension _ColorShadeExtension on Color {
  Color darken(double amount) {
    assert(amount >= 0 && amount <= 1);
    final f = 1 - amount;
    return Color.fromARGB(
      alpha,
      (red * f).round(),
      (green * f).round(),
      (blue * f).round(),
    );
  }
}
