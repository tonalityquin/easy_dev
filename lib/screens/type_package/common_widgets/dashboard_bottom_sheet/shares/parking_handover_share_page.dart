import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../../../states/user/user_state.dart';
import '../../../../../utils/block_dialogs/duration_blocking_dialog.dart';
import '../../../../../utils/snackbar_helper.dart';

import '../../../parking_completed_package/table_package/models/parking_completed_record.dart';
import '../../../parking_completed_package/table_package/repositories/parking_completed_repository.dart';

/// Deep Blue 팔레트(서비스 카드 계열과 통일)
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 톤 변형/보더
  static const fg = Colors.white; // 전경(아이콘/텍스트)
}

/// ParkingCompleted 테이블을 Firestore로 "한 번에 공유"하는 헬퍼
/// - parking_completed_shares/{roomId}/exports/latest 에
///   records 배열로 한 문서에 몽땅 넣어서 1 write로 업로드
Future<void> _shareParkingTableOnce({
  required String roomId,
  required String senderName,
  required List<ParkingCompletedRecord> rows,
}) async {
  final firestore = FirebaseFirestore.instance;

  final exportsCol =
  firestore.collection('parking_completed_shares').doc(roomId).collection('exports');

  // 🔹 이 room은 항상 latest 하나만 유지
  final exportRef = exportsCol.doc('latest');

  final recordsJson = rows.map((r) {
    final m = r.toMap();
    // 로컬 SQLite용 id는 공유에는 불필요하므로 제거
    m.remove('id');
    return m;
  }).toList();

  await exportRef.set({
    'records': recordsJson,
    'rowCount': recordsJson.length,
    'senderName': senderName,
    'sentAt': FieldValue.serverTimestamp(),
  });
}

/// Firestore에서 해당 roomId의 "최신 공유본 1개(latest 문서)"를 읽어서
/// 로컬 SQLite ParkingCompleted 테이블에 적용하는 헬퍼
Future<void> _importLatestShare({
  required BuildContext context,
  required String roomId,
}) async {
  try {
    final firestore = FirebaseFirestore.instance;

    final exportsCol =
    firestore.collection('parking_completed_shares').doc(roomId).collection('exports');

    final docSnap = await exportsCol.doc('latest').get();

    if (!docSnap.exists) {
      showSelectedSnackbar(context, '가져올 공유 데이터가 없습니다.');
      return;
    }

    final data = docSnap.data() ?? <String, dynamic>{};

    final List<dynamic> recordsJson = (data['records'] as List<dynamic>? ?? <dynamic>[]);

    if (recordsJson.isEmpty) {
      showSelectedSnackbar(context, '공유된 records 배열이 비어 있습니다.');
      return;
    }

    final repo = ParkingCompletedRepository();
    int insertedCount = 0;

    for (final item in recordsJson) {
      if (item is Map<String, dynamic>) {
        final map = Map<String, Object?>.from(item);
        final record = ParkingCompletedRecord.fromMap(map);

        // insert는 UNIQUE(plate, area, created_at) + CONFLICT IGNORE 이므로
        // 중복이면 0, 새로 들어가면 1 레코드 삽입됨
        final n = await repo.insert(record);
        if (n > 0) insertedCount += n;
      }
    }

    showSuccessSnackbar(
      context,
      '가져오기 완료: $insertedCount건 추가되었습니다.',
    );
  } catch (e) {
    showFailedSnackbar(context, '가져오기 실패: $e');
  }
}

/// 업무 인수인계용 Parking Completed 공유/가져오기 화면
class ParkingHandoverSharePage extends StatefulWidget {
  const ParkingHandoverSharePage({Key? key}) : super(key: key);

  @override
  State<ParkingHandoverSharePage> createState() => _ParkingHandoverSharePageState();
}

class _ParkingHandoverSharePageState extends State<ParkingHandoverSharePage> {
  bool isExporting = false;
  bool isImporting = false;
  int? lastExportedCount;
  int? lastImportedCount;
  String? lastError;

  Future<void> _handleShare() async {
    final userState = context.read<UserState>();
    final currentUser = userState.user;
    final String roomId = currentUser?.currentArea?.trim() ?? '';
    final String senderName = userState.name;

    if (roomId.isEmpty) {
      showFailedSnackbar(
        context,
        '공유를 위해 currentArea가 설정되어야 합니다.',
      );
      return;
    }

    final proceed = await showDurationBlockingDialog(
      context,
      message: '5초 후에 입차 완료 현황을 공유합니다.\n'
          '공유를 원하지 않으면 [취소]를 눌러 주세요.',
    );

    if (!proceed) {
      showSelectedSnackbar(context, '공유가 취소되었습니다.');
      return;
    }

    setState(() {
      isExporting = true;
      lastExportedCount = null;
      lastError = null;
    });

    try {
      final repo = ParkingCompletedRepository();
      final rows = await repo.listAll(limit: 500);

      if (rows.isEmpty) {
        showSelectedSnackbar(
          context,
          '공유할 Parking Completed 기록이 없습니다.',
        );
      } else {
        await _shareParkingTableOnce(
          roomId: roomId,
          senderName: senderName,
          rows: rows,
        );
        setState(() {
          lastExportedCount = rows.length;
        });
        showSuccessSnackbar(
          context,
          '기록 ${rows.length}건을 공유했습니다.',
        );
      }
    } catch (e) {
      setState(() {
        lastError = e.toString();
      });
      showFailedSnackbar(context, '공유 실패: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        isExporting = false;
      });
    }
  }

  Future<void> _handleImport() async {
    final userState = context.read<UserState>();
    final currentUser = userState.user;
    final String roomId = currentUser?.currentArea?.trim() ?? '';

    if (roomId.isEmpty) {
      showFailedSnackbar(
        context,
        '가져오기를 위해 currentArea가 설정되어야 합니다.',
      );
      return;
    }

    final proceed = await showDurationBlockingDialog(
      context,
      message: '가장 최근 공유 데이터를 가져오고 있습니다.\n'
          '가져오기를 원하지 않으면 [취소]를 눌러 주세요.',
    );

    if (!proceed) {
      showSelectedSnackbar(context, '가져오기가 취소되었습니다.');
      return;
    }

    setState(() {
      isImporting = true;
      lastImportedCount = null;
      lastError = null;
    });

    try {
      await _importLatestShare(context: context, roomId: roomId);
      setState(() {
        lastImportedCount = 0; // "시도 완료" 표시용 플래그
      });
    } catch (e) {
      setState(() {
        lastError = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        isImporting = false;
      });
    }
  }

  String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    EdgeInsetsGeometry? margin,
  }) {
    return Card(
      elevation: 0,
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      color: Colors.white,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _gap(double h) => SizedBox(height: h);

  @override
  Widget build(BuildContext context) {
    final userState = context.read<UserState>();
    final currentUser = userState.user;
    final String roomId = currentUser?.currentArea?.trim() ?? '';
    final String senderName = userState.name;

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final hasStatus =
        lastExportedCount != null || lastImportedCount != null || lastError != null;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      // 문서 느낌 배경
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('업무 인수인계'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: Colors.black12, width: 1),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 상단 제목 (문서 타이틀)
                        Text(
                          '업무 인수인계 메모',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'PARKING HANDOVER NOTE',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.black54,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 실제 "종이" 느낌의 인수인계 문서 카드
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _Palette.light.withOpacity(0.8),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 상단 메타 정보 라인
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _Palette.base.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.swap_horiz,
                                      size: 20,
                                      color: _Palette.dark,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Parking 현황 인수인계',
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: _Palette.dark,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '입차 완료 테이블을 기준으로 근무 교대 간 인수인계를 진행합니다.',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '근무 구역: ${roomId.isEmpty ? "미설정" : roomId}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '작성일 ${_fmtCompact(DateTime.now())}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Divider(height: 24),
                              const SizedBox(height: 4),

                              // 안내 문구 (공통)
                              Container(
                                decoration: BoxDecoration(
                                  color: _Palette.light.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _Palette.light.withOpacity(0.7),
                                  ),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      size: 18,
                                      color: _Palette.dark,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '출근자와 퇴근자가 같은 구역(roomId)을 기준으로 '
                                            '입차 완료 내역을 공유/가져오기 하여, 인수인계 내용을 명확히 남길 수 있습니다.',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              _gap(20),

                              // 섹션 1. 출근조 안내
                              _sectionCard(
                                title: '1. 출근조 안내 (공유자)',
                                margin: const EdgeInsets.only(bottom: 16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: _Palette.base,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.login,
                                        color: _Palette.fg,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '출근자의 단말기에 저장된 입차 완료 차량 내역을 기준으로 합니다.\n'
                                            '근무가 끝나기 전에 아래 [입차 완료 현황 테이블 공유하기] 버튼을 눌러\n'
                                            '해당 구역(roomId)의 최신 현황을 Firestore에 한 번 업로드해 주세요.',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: cs.onSurface.withOpacity(0.8),
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // 섹션 2. 근무 정보 요약
                              _sectionCard(
                                title: '2. 현재 근무 정보',
                                margin: const EdgeInsets.only(bottom: 16),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceVariant.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: DefaultTextStyle(
                                    style: textTheme.bodySmall!.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.map_outlined,
                                              size: 18,
                                              color: _Palette.dark,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text('구역(roomId): '),
                                            Expanded(
                                              child: Text(
                                                roomId.isEmpty ? '(미설정)' : roomId,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.person_outline,
                                              size: 18,
                                              color: _Palette.dark,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text('담당자: '),
                                            Expanded(
                                              child: Text(
                                                senderName.isEmpty ? '(알 수 없음)' : senderName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // 섹션 3. 퇴근조 안내
                              _sectionCard(
                                title: '3. 퇴근조 안내 (인수자)',
                                margin: const EdgeInsets.only(bottom: 20),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: _Palette.base,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.logout,
                                        color: _Palette.fg,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '마지막 조 또는 다음 근무자는 [가장 최근 공유 가져오기] 버튼을 눌러\n'
                                            '같은 구역(roomId)에 업로드된 최신 입차 완료 내역을 단말기로 내려받습니다.\n'
                                            '이 정보를 기준으로 마감 처리 및 다음 근무 준비를 진행합니다.',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: cs.onSurface.withOpacity(0.8),
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // 섹션 4. 작업 영역 (버튼/상태)
                              _sectionCard(
                                title: '4. 작업',
                                margin: EdgeInsets.zero,
                                padding:
                                const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                                child: _WorkActionCard(
                                  cs: cs,
                                  textTheme: textTheme,
                                  roomId: roomId,
                                  isExporting: isExporting,
                                  isImporting: isImporting,
                                  lastError: lastError,
                                  lastExportedCount: lastExportedCount,
                                  lastImportedCount: lastImportedCount,
                                  onShare: _handleShare,
                                  onImport: _handleImport,
                                  hasStatus: hasStatus,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 하단 "작업" 카드 위젯
class _WorkActionCard extends StatelessWidget {
  const _WorkActionCard({
    required this.cs,
    required this.textTheme,
    required this.roomId,
    required this.isExporting,
    required this.isImporting,
    required this.lastError,
    required this.lastExportedCount,
    required this.lastImportedCount,
    required this.onShare,
    required this.onImport,
    required this.hasStatus,
  });

  final ColorScheme cs;
  final TextTheme textTheme;

  final String roomId;
  final bool isExporting;
  final bool isImporting;
  final String? lastError;
  final int? lastExportedCount;
  final int? lastImportedCount;
  final VoidCallback onShare;
  final VoidCallback onImport;
  final bool hasStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '실행 버튼',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          // 공유 버튼
          ElevatedButton.icon(
            onPressed: (roomId.isEmpty || isExporting || isImporting) ? null : onShare,
            icon: isExporting
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _Palette.fg,
                ),
              ),
            )
                : const Icon(Icons.share),
            label: Text(
              isExporting ? '공유 중…' : '입차 완료 현황 테이블 공유하기',
              textAlign: TextAlign.center,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _Palette.base,
              foregroundColor: _Palette.fg,
              padding: const EdgeInsets.symmetric(
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 가져오기 버튼
          OutlinedButton.icon(
            onPressed: (roomId.isEmpty || isImporting || isExporting) ? null : onImport,
            icon: isImporting
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.download),
            label: Text(
              isImporting ? '가져오는 중…' : '가장 최근 공유 가져오기',
              textAlign: TextAlign.center,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _Palette.dark,
              side: BorderSide(
                color: _Palette.light.withOpacity(.8),
              ),
              padding: const EdgeInsets.symmetric(
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // 상태 표시(마지막 공유/가져오기 결과)
          if (hasStatus) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceVariant.withOpacity(0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    lastError != null ? Icons.error_outline : Icons.check_circle_outline,
                    size: 18,
                    color: lastError != null ? cs.error : _Palette.dark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lastError != null
                          ? '마지막 오류: $lastError'
                          : [
                        if (lastExportedCount != null) '마지막 공유: $lastExportedCount건 전송 완료',
                        if (lastImportedCount != null) '마지막 가져오기 시도 완료',
                      ].join(' / '),
                      style: textTheme.bodySmall?.copyWith(
                        color: lastError != null ? cs.error : cs.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
