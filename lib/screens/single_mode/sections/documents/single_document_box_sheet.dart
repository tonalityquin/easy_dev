import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../../states/area/area_state.dart';

import '../../../../repositories/commute_repo_services/commute_log_repository.dart';
import '../../../../utils/block_dialogs/break_duration_blocking_dialog.dart';
import '../../../../utils/block_dialogs/work_end_duration_blocking_dialog.dart';
import '../../utils/att_brk_mode_db.dart';
import '../../../common_package/document_package/backup/backup_form_page.dart';
import '../../../common_package/document_package/user_statement/user_statement_form_page.dart';
import 'single_document_inventory_repository.dart';
import 'single_document_item.dart';

Future<void> openSingleDocumentBox(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _SingleDocumentBoxSheet(),
  );
}

class _SingleDocumentBoxSheet extends StatelessWidget {
  const _SingleDocumentBoxSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final userState = context.watch<UserState>();
    final repo = SingleDocumentInventoryRepository.instance;

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
                    color: cs.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withOpacity(0.10),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
                  ),
                  child: Row(
                    children: [
                      const _BinderSpine(),
                      VerticalDivider(
                        width: 0,
                        thickness: 0.8,
                        color: cs.outlineVariant.withOpacity(0.8),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const _SheetHeader(),
                            Divider(
                              height: 1,
                              thickness: 0.8,
                              color: cs.outlineVariant.withOpacity(0.8),
                            ),
                            Expanded(
                              child: StreamBuilder<List<SingleDocumentItem>>(
                                stream: repo.streamForUser(userState),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return Center(
                                      child: CircularProgressIndicator(color: cs.primary),
                                    );
                                  }

                                  final items = snapshot.data ?? const <SingleDocumentItem>[];
                                  if (items.isEmpty) {
                                    return const _EmptyState();
                                  }

                                  return ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return _DocumentListItem(
                                        item: item,
                                        onTap: () async {
                                          switch (item.type) {
                                            case SingleDocumentType.statementForm:
                                              if (item.id == 'template-commute-record') {
                                                final proceed = await showWorkEndDurationBlockingDialog(
                                                  context,
                                                  message: '단말기에 저장된 출퇴근 기록을\n서버에 제출합니다.\n\n'
                                                      '제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
                                                  duration: const Duration(seconds: 5),
                                                );
                                                if (!proceed) return;
                                                await _submitCommuteRecordsFromSqlite(context);
                                              } else if (item.id == 'template-resttime-record') {
                                                final proceed = await showBreakDurationBlockingDialog(
                                                  context,
                                                  message: '단말기에 저장된 휴게시간 기록을\n서버에 제출합니다.\n\n'
                                                      '제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
                                                  duration: const Duration(seconds: 5),
                                                );
                                                if (!proceed) return;
                                                await _submitRestTimeRecordsFromSqlite(context);
                                              } else {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => const UserStatementFormPage(),
                                                    fullscreenDialog: true,
                                                  ),
                                                );
                                              }
                                              break;

                                            case SingleDocumentType.handoverForm:
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('인수인계 양식은 현재 Single 모드에서 사용하지 않습니다.'),
                                                ),
                                              );
                                              break;

                                            case SingleDocumentType.workEndReportForm:
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('업무 종료/퇴근 보고 양식은 현재 Single 모드에서 사용하지 않습니다.'),
                                                ),
                                              );
                                              break;

                                            case SingleDocumentType.workStartReportForm:
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('업무 시작 보고 양식은 현재 Single 모드에서 사용하지 않습니다.'),
                                                ),
                                              );
                                              break;

                                            case SingleDocumentType.generic:
                                              if (item.id == 'template-annual-leave-application') {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => const BackupFormPage(),
                                                    fullscreenDialog: true,
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

/// 상단 드래그 핸들
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 64,
        height: 6,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cs.outlineVariant.withOpacity(0.9),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// 문서철 왼쪽 스파인(바인더 느낌)
class _BinderSpine extends StatelessWidget {
  const _BinderSpine();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 32,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24)),
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
                color: cs.outlineVariant.withOpacity(0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.15),
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

/// 상단 헤더
class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.75),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.folder_special_outlined,
              size: 22,
              color: cs.onPrimaryContainer,
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
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '경위서, 출퇴근·휴게 기록, 신청/사직서 양식을 한 곳에 모았어요.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '닫기',
            icon: Icon(Icons.close, size: 20, color: cs.onSurfaceVariant),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// 문서 리스트 아이템
class _DocumentListItem extends StatelessWidget {
  final SingleDocumentItem item;
  final VoidCallback onTap;

  const _DocumentListItem({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accentColor = _accentColorForItem(context, item);
    final typeLabel = _typeLabelForItem(item);
    final iconData = _iconForItem(item);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.06),
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
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: accentColor.withOpacity(0.16),
                        child: Icon(iconData, color: accentColor, size: 20),
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
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _buildSubtitle(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: accentColor.withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    typeLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: accentColor,
                                      fontWeight: FontWeight.w700,
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
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: cs.onSurfaceVariant.withOpacity(0.75),
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

/// ─────────────────────────
/// SQLite → Firestore 동기화용 모델/함수 (기능 변경 없음)
/// ─────────────────────────

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

Future<void> _submitCommuteRecordsFromSqlite(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);

  final userState = context.read<UserState>();
  final areaState = context.read<AreaState>();

  final userId = (userState.user?.id ?? '').trim();
  final userName = userState.name.trim();
  final area = (userState.user?.selectedArea ?? '').trim();
  final division = areaState.currentDivision.trim();

  if (userId.isEmpty || userName.isEmpty || area.isEmpty || division.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          '출퇴근 기록 제출 실패: 사용자/근무지 정보가 비어 있습니다.\n'
              '관리자에게 계정 및 근무지 설정을 확인해 달라고 요청해 주세요.',
        ),
      ),
    );
    return;
  }

  try {
    final records = await _loadLocalCommuteRecordsFromSqlite(
      context: context,
      statuses: const ['출근', '퇴근'],
      userId: userId,
    );

    if (records.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('제출할 출퇴근 기록이 없습니다.')));
      return;
    }

    final repo = CommuteLogRepository();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');

    var successCount = 0;
    var skippedCount = 0;
    var failedCount = 0;
    var deletedCount = 0;

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

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '출퇴근 기록 제출 완료: '
              '$successCount건 업로드, '
              '중복 $skippedCount건, '
              '실패 $failedCount건, '
              '로컬 삭제 $deletedCount건.',
        ),
      ),
    );
  } catch (e) {
    debugPrint('❌ 출퇴근 기록 제출 중 오류: $e');
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          '출퇴근 기록 제출 중 오류가 발생했습니다.\n'
              '네트워크 또는 Firebase 설정을 확인해 주세요.',
        ),
      ),
    );
  }
}

Future<void> _submitRestTimeRecordsFromSqlite(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);

  final userState = context.read<UserState>();
  final areaState = context.read<AreaState>();

  final userId = (userState.user?.id ?? '').trim();
  final userName = userState.name.trim();
  final area = (userState.user?.selectedArea ?? '').trim();
  final division = areaState.currentDivision.trim();

  if (userId.isEmpty || userName.isEmpty || area.isEmpty || division.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          '휴게시간 기록 제출 실패: 사용자/근무지 정보가 비어 있습니다.\n'
              '관리자에게 계정 및 근무지 설정을 확인해 달라고 요청해 주세요.',
        ),
      ),
    );
    return;
  }

  try {
    final records = await _loadLocalCommuteRecordsFromSqlite(
      context: context,
      statuses: const ['휴게'],
      userId: userId,
    );

    if (records.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('제출할 휴게시간 기록이 없습니다.')));
      return;
    }

    final repo = CommuteLogRepository();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');

    var successCount = 0;
    var skippedCount = 0;
    var failedCount = 0;
    var deletedCount = 0;

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
        skippedCount++;
        deletedCount += await _deleteLocalAttendanceRow(record);
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
        successCount++;
        deletedCount += await _deleteLocalAttendanceRow(record);
      } else {
        failedCount++;
      }
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '휴게시간 기록 제출 완료: '
              '$successCount건 업로드, '
              '중복 $skippedCount건, '
              '실패 $failedCount건, '
              '로컬 삭제 $deletedCount건.',
        ),
      ),
    );
  } catch (e) {
    debugPrint('❌ 휴게시간 기록 제출 중 오류: $e');
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          '휴게시간 기록 제출 중 오류가 발생했습니다.\n'
              '네트워크 또는 Firebase 설정을 확인해 주세요.',
        ),
      ),
    );
  }
}

String _buildSubtitle(SingleDocumentItem item) {
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
    // 연차/결근 신청서는 중립톤(보더 계열)로
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
