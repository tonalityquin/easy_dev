import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../../states/area/area_state.dart';

import '../../../../../../repositories/commute_log_repository.dart';
import '../../../../../../utils/block_dialogs/break_duration_blocking_dialog.dart';
import '../../../../../../utils/block_dialogs/work_end_duration_blocking_dialog.dart';
import '../../../../../hubs_mode/dev_package/debug_package/debug_database_logger.dart';
import '../../../../../simple_mode/utils/simple_mode/simple_mode_db.dart';

import '../backup/lite_backup_form_page.dart';
import '../work_start_report/sections/lite_dashboard_end_report_form_page.dart';
import '../work_start_report/sections/lite_dashboard_start_report_form_page.dart';
import 'lite_fielder_document_inventory_repository.dart';
import 'lite_user_statement_form_page.dart';
import 'lite_document_item.dart';
import '../shares/lite_parking_handover_share_page.dart';

Future<void> openFielderDocumentBox(BuildContext context) async {
  await showModalBottomSheet<void>(
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
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }

                                  final items = snapshot.data ?? const <DocumentItem>[];

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
                                        onTap: () async {
                                          switch (item.type) {
                                            case DocumentType.statementForm:
                                            // ✅ statementForm 안에서 id 기준 분기
                                              if (item.id == 'template-commute-record') {
                                                // 출퇴근 기록 제출
                                                final proceed = await showWorkEndDurationBlockingDialog(
                                                  context,
                                                  message: '단말기에 저장된 출퇴근 기록을\n서버에 제출합니다.\n\n'
                                                      '제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
                                                  duration: const Duration(seconds: 5),
                                                );
                                                if (!proceed) return;

                                                await _submitCommuteRecordsFromSqlite(context);
                                              } else if (item.id == 'template-resttime-record') {
                                                // 휴게시간 기록 제출
                                                final proceed = await showBreakDurationBlockingDialog(
                                                  context,
                                                  message: '단말기에 저장된 휴게시간 기록을\n서버에 제출합니다.\n\n'
                                                      '제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
                                                  duration: const Duration(seconds: 5),
                                                );
                                                if (!proceed) return;

                                                await _submitRestTimeRecordsFromSqlite(context);
                                              } else {
                                                // 그 외(일반 경위서) → 경위서 작성 화면
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => const UserStatementFormPage(),
                                                    fullscreenDialog: true,
                                                  ),
                                                );
                                              }
                                              break;

                                            case DocumentType.handoverForm:
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => const ParkingHandoverSharePage(),
                                                  fullscreenDialog: true,
                                                ),
                                              );
                                              break;

                                            case DocumentType.workEndReportForm:
                                            // ✅ 업무 종료/퇴근 보고 양식은 모두 새 DashboardEndReportFormPage 로 이동
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => const DashboardEndReportFormPage(),
                                                  fullscreenDialog: true,
                                                ),
                                              );
                                              break;

                                            case DocumentType.workStartReportForm:
                                            // ✅ 업무 시작 보고 양식 → 새로 만든 화면으로 이동
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => const DashboardStartReportFormPage(),
                                                  fullscreenDialog: true,
                                                ),
                                              );
                                              break;

                                            case DocumentType.generic:
                                            // ✅ generic 문서 중 연차(결근) 지원 신청서 연결
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

/// 문서철 왼쪽 스파인(바인더 느낌)
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

/// 상단 헤더(문서철 제목/설명)
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

/// 각각의 문서를 카드 형태로 보여주는 위젯
class _DocumentListItem extends StatelessWidget {
  final DocumentItem item;
  final VoidCallback onTap;

  const _DocumentListItem({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColorForItem(item); // ← item 기준 색상
    final typeLabel = _typeLabelForItem(item); // ← item 기준 라벨
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
              // 좌측 컬러 인덱스 바
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

/// ─────────────────────────
/// SQLite → Firestore 동기화용 모델/함수 (출퇴근/휴게 기록)
/// ─────────────────────────

/// SQLite에서 읽어 온 출근/퇴근/휴게 1건
class LocalCommuteRecord {
  /// Firestore 상태 라벨: "출근" / "퇴근" / "휴게"
  final String status;

  /// 실제 이벤트 시각 (date + time 기준)
  final DateTime dateTime;

  /// 로컬 SQLite 테이블명 (simple_work_attendance / simple_break_attendance)
  final String localTable;

  /// 로컬 SQLite date 값(yyyy-MM-dd)
  final String localDate;

  /// 로컬 SQLite type 값(work_in/work_out/start)
  final String localType;

  LocalCommuteRecord({
    required this.status,
    required this.dateTime,
    required this.localTable,
    required this.localDate,
    required this.localType,
  });
}

/// SQLite(simple_work_attendance / simple_break_attendance)에서
/// 출근/퇴근/휴게 데이터를 전부 읽어 오는 함수.
///
/// [statuses] 는 Firestore 상태 라벨 기준:
///   - ["출근", "퇴근"]
///   - ["휴게"]
Future<List<LocalCommuteRecord>> _loadLocalCommuteRecordsFromSqlite({
  required BuildContext context,
  required List<String> statuses,
  required String userId, // 현재 스키마상 userId 컬럼은 없으므로 필터에는 사용하지 않음
}) async {
  final db = await SimpleModeDb.instance.database;
  final result = <LocalCommuteRecord>[];

  final dateTimeParser = DateFormat('yyyy-MM-dd HH:mm');

  // 1) 출근/퇴근 (simple_work_attendance)
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
      final dateStr = row['date'] as String; // yyyy-MM-dd
      final timeStr = row['time'] as String; // HH:mm

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
        // 파싱 실패는 무시
        continue;
      }
    }
  }

  // 2) 휴게 (simple_break_attendance, type = "start")
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

/// 업로드(또는 서버 중복으로 간주)된 로컬 행을 삭제합니다.
/// - (date, type) 기준 1건 삭제
Future<int> _deleteLocalAttendanceRow(LocalCommuteRecord record) async {
  final db = await SimpleModeDb.instance.database;
  return db.delete(
    record.localTable,
    where: 'date = ? AND type = ?',
    whereArgs: [record.localDate, record.localType],
  );
}

/// 출퇴근 기록 제출:
/// - SQLite(simple_work_attendance)에 있는 출근/퇴근 전체 →
///   Firestore(commute_user_logs)의 "출근"/"퇴근" 로그로 업로드
Future<void> _submitCommuteRecordsFromSqlite(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);

  // 사용자/근무지 정보
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
    // 1) SQLite에서 출근/퇴근 전체 로딩
    final records = await _loadLocalCommuteRecordsFromSqlite(
      context: context,
      statuses: const ['출근', '퇴근'],
      userId: userId,
    );

    if (records.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('제출할 출퇴근 기록이 없습니다.'),
        ),
      );
      return;
    }

    final repo = CommuteLogRepository();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');

    var successCount = 0;
    var skippedCount = 0;
    var deletedCount = 0;
    var failedCount = 0;

    // 2) Firestore commute_user_logs 에 업로드
    for (final record in records) {
      final status = record.status; // "출근" 또는 "퇴근"
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
        // 서버에 이미 존재하는 경우, 로컬은 제출 완료로 간주하고 정리
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

      // ✅ addLog가 예외를 흡수하거나 네트워크/권한 문제로 실제 반영이 안 될 수 있으므로 재검증
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
          '출퇴근 기록 제출 결과: '
              '$successCount건 업로드, '
              '서버 중복 $skippedCount건, '
              '실패 $failedCount건, '
              '로컬 정리 $deletedCount건.',
        ),
      ),
    );
  } catch (e, st) {
    debugPrint('❌ [FielderDocumentBoxSheet] 출퇴근 기록 제출 중 오류: $e');

    try {
      await DebugDatabaseLogger().log(
        {
          'tag': 'FielderDocumentBoxSheet._submitCommuteRecordsFromSqlite',
          'message': '출퇴근 기록 Firestore 동기화 중 예외 발생',
          'error': e.toString(),
          'stack': st.toString(),
        },
        level: 'error',
        tags: const ['database', 'firestore', 'commute', 'migration'],
      );
    } catch (_) {}

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

/// 휴게시간 기록 제출:
/// - SQLite(simple_break_attendance)에 있는 휴게 로그 전체 →
///   Firestore(commute_user_logs)의 "휴게" 로그로 업로드
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
    // 1) SQLite에서 휴게 로그 전체 로딩
    final records = await _loadLocalCommuteRecordsFromSqlite(
      context: context,
      statuses: const ['휴게'],
      userId: userId,
    );

    if (records.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('제출할 휴게시간 기록이 없습니다.'),
        ),
      );
      return;
    }

    final repo = CommuteLogRepository();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');

    var successCount = 0;
    var skippedCount = 0;
    var deletedCount = 0;
    var failedCount = 0;

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
        // 서버에 이미 존재하는 경우, 로컬은 제출 완료로 간주하고 정리
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
          '휴게시간 기록 제출 결과: '
              '$successCount건 업로드, '
              '서버 중복 $skippedCount건, '
              '실패 $failedCount건, '
              '로컬 정리 $deletedCount건.',
        ),
      ),
    );
  } catch (e, st) {
    debugPrint('❌ [FielderDocumentBoxSheet] 휴게시간 기록 제출 중 오류: $e');

    try {
      await DebugDatabaseLogger().log(
        {
          'tag': 'FielderDocumentBoxSheet._submitRestTimeRecordsFromSqlite',
          'message': '휴게시간 기록 Firestore 동기화 중 예외 발생',
          'error': e.toString(),
          'stack': st.toString(),
        },
        level: 'error',
        tags: const ['database', 'firestore', 'break', 'migration'],
      );
    } catch (_) {}

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

/// ─────────────────────────
/// 디자인/텍스트 헬퍼 함수 모음
/// ─────────────────────────

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

/// 기본 type 기준 색상
Color _accentColorForType(DocumentType type) {
  switch (type) {
    case DocumentType.workStartReportForm:
      return const Color(0xFF4F9A94); // 청록
    case DocumentType.workEndReportForm:
      return const Color(0xFFEF6C53); // 기본 오렌지/레드
    case DocumentType.handoverForm:
      return const Color(0xFF8D6E63); // 브라운
    case DocumentType.statementForm:
      return const Color(0xFF5C6BC0); // 블루
    case DocumentType.generic:
      return const Color(0xFF757575);
  }
}

/// type + id 기준으로 색상 세분화 (퇴근 vs 업무 종료)
Color _accentColorForItem(DocumentItem item) {
  if (item.type == DocumentType.workEndReportForm) {
    if (item.id == 'template-work-end-report') {
      // 퇴근 보고 양식: 기존 오렌지톤
      return const Color(0xFFEF6C53);
    }
    if (item.id == 'template-end-work-report') {
      // 업무 종료 보고서: 좀 더 진한 레드톤
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
    case DocumentType.handoverForm:
      return Icons.swap_horiz;
    case DocumentType.statementForm:
      return Icons.description_outlined;
    case DocumentType.generic:
      return Icons.insert_drive_file_outlined;
  }
}

/// type + id 기준으로 라벨을 세분화
String _typeLabelForItem(DocumentItem item) {
  // 1) 퇴근 vs 업무 종료 세분화
  if (item.type == DocumentType.workEndReportForm) {
    if (item.id == 'template-work-end-report') {
      return '퇴근 보고';
    }
    if (item.id == 'template-end-work-report') {
      return '업무 종료 보고';
    }
  }

  // 2) 경위서 계열(출퇴근/휴게 기록) 세분화
  if (item.type == DocumentType.statementForm) {
    switch (item.id) {
      case 'template-commute-record':
        return '출퇴근 기록';
      case 'template-resttime-record':
        return '휴게시간 기록';
    }
  }

  // 3) 그 외는 type 기본 라벨
  return _typeLabelForType(item.type);
}

String _typeLabelForType(DocumentType type) {
  switch (type) {
    case DocumentType.workStartReportForm:
      return '업무 시작 보고';
    case DocumentType.workEndReportForm:
    // 기본값(위에서 id별로 override 가능)
      return '퇴근/업무 종료';
    case DocumentType.handoverForm:
      return '업무 인수인계';
    case DocumentType.statementForm:
      return '경위서';
    case DocumentType.generic:
      return '기타 문서';
  }
}

/// Color 확장: 약간 어둡게
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
