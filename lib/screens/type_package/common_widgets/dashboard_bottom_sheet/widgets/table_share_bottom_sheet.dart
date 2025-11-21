import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../../../states/user/user_state.dart';
import '../../../../../utils/snackbar_helper.dart';
import '../../../parking_completed_package/repositories/parking_completed_repository.dart';
import '../../../parking_completed_package/models/parking_completed_record.dart';

// 🔹 새로 분리한 다이얼로그 헬퍼 import (같은 폴더 기준)
import 'table_share_blocking_dialog.dart';

/// Deep Blue 팔레트(서비스 카드 계열과 통일)
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 톤 변형/보더
  static const fg = Colors.white; // 전경(아이콘/텍스트)
}

/// ParkingCompleted 테이블을 Firestore로 "한 번에 공유"하는 헬퍼
/// - parkingCompletedShares/{roomId}/exports/latest 에
///   records 배열로 한 문서에 몽땅 넣어서 1 write로 업로드
Future<void> _shareParkingTableOnce({
  required String roomId,
  required String senderName,
  required List<ParkingCompletedRecord> rows,
}) async {
  final firestore = FirebaseFirestore.instance;

  final exportsCol =
  firestore.collection('parkingCompletedShares').doc(roomId).collection('exports');

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
    firestore.collection('parkingCompletedShares').doc(roomId).collection('exports');

    // 🔹 더 이상 orderBy/limit 불필요, latest 문서만 사용
    final docSnap = await exportsCol.doc('latest').get();

    if (!docSnap.exists) {
      showSelectedSnackbar(context, '가져올 공유 데이터가 없습니다.');
      return;
    }

    final data = docSnap.data() ?? <String, dynamic>{};

    final List<dynamic> recordsJson =
    (data['records'] as List<dynamic>? ?? <dynamic>[]);

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

/// "테이블 공유" 바텀시트
/// - ParkingCompleted SQLite 테이블을
///   현재 구역(roomId) 기준으로 Firestore에 공유/수신하는 UI를 제공
/// - 채팅 바텀시트와 동일하게 화면 최상단(SafeArea 상단)까지 올라오도록 구성
Future<void> tableShareBottomSheet(BuildContext context) async {
  // 바텀시트 내부에서 사용할 상태 변수들
  bool isExporting = false;
  bool isImporting = false;
  int? lastExportedCount;
  int? lastImportedCount;
  String? lastError;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.25),
    builder: (ctx) {
      final inset = MediaQuery.of(ctx).viewInsets.bottom; // 키보드 높이

      // UserState에서 roomId, senderName 가져오기
      final userState = ctx.read<UserState>();
      final currentUser = userState.user;
      final String roomId = currentUser?.currentArea?.trim() ?? '';
      final String senderName = userState.name;

      return AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: inset),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height, // 전체 높이
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 16,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: true,
                  left: false,
                  right: false,
                  bottom: false,
                  child: StatefulBuilder(
                    builder: (ctx, setModalState) {
                      Future<void> handleShare() async {
                        if (roomId.isEmpty) {
                          showFailedSnackbar(
                            ctx,
                            '공유를 위해 currentArea가 설정되어야 합니다.',
                          );
                          return;
                        }

                        // 🔹 5초짜리 취소 가능 blocking dialog (분리된 파일의 함수 사용)
                        final proceed = await showCancelableBlockingDialog(
                          ctx,
                          message: '5초 후에 입차 완료 현황을 공유합니다.\n'
                              '공유를 원하지 않으면 [취소]를 눌러 주세요.',
                        );

                        if (!proceed) {
                          showSelectedSnackbar(ctx, '공유가 취소되었습니다.');
                          return;
                        }

                        setModalState(() {
                          isExporting = true;
                          lastExportedCount = null;
                          lastError = null;
                        });

                        try {
                          // 1) 로컬 SQLite에서 테이블 전체(또는 최대 N건) 조회
                          final repo = ParkingCompletedRepository();
                          final rows = await repo.listAll(limit: 500);

                          if (rows.isEmpty) {
                            showSelectedSnackbar(
                              ctx,
                              '공유할 Parking Completed 기록이 없습니다.',
                            );
                          } else {
                            // 2) Firestore 한 문서(latest)에 records 배열로 업로드 (1 write)
                            await _shareParkingTableOnce(
                              roomId: roomId,
                              senderName: senderName,
                              rows: rows,
                            );
                            lastExportedCount = rows.length;
                            showSuccessSnackbar(
                              ctx,
                              '기록 ${rows.length}건을 공유했습니다.',
                            );
                          }
                        } catch (e) {
                          lastError = e.toString();
                          showFailedSnackbar(ctx, '공유 실패: $e');
                        } finally {
                          setModalState(() {
                            isExporting = false;
                          });
                        }
                      }

                      Future<void> handleImport() async {
                        if (roomId.isEmpty) {
                          showFailedSnackbar(
                            ctx,
                            '가져오기를 위해 currentArea가 설정되어야 합니다.',
                          );
                          return;
                        }

                        // 🔹 5초짜리 취소 가능 blocking dialog (분리된 파일의 함수 사용)
                        final proceed = await showCancelableBlockingDialog(
                          ctx,
                          message: '5초 후에 가장 최근 공유 데이터를 가져옵니다.\n'
                              '가져오기를 원하지 않으면 [취소]를 눌러 주세요.',
                        );

                        if (!proceed) {
                          showSelectedSnackbar(ctx, '가져오기가 취소되었습니다.');
                          return;
                        }

                        setModalState(() {
                          isImporting = true;
                          lastImportedCount = null;
                          lastError = null;
                        });

                        try {
                          await _importLatestShare(context: ctx, roomId: roomId);
                          lastImportedCount ??= 0;
                        } catch (e) {
                          lastError = e.toString();
                        } finally {
                          setModalState(() {
                            isImporting = false;
                          });
                        }
                      }

                      final cs = Theme.of(ctx).colorScheme;
                      final textTheme = Theme.of(ctx).textTheme;

                      final hasStatus =
                          lastExportedCount != null || lastImportedCount != null || lastError != null;

                      return Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          const SizedBox(height: 12),
                          // 상단 드래그 핸들
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // ───────────── 헤더: 타이틀 + 닫기 ─────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.send_to_mobile,
                                  color: _Palette.base,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Parking Completed 공유/가져오기',
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: _Palette.dark,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '닫기',
                                  icon: Icon(
                                    Icons.close,
                                    color: _Palette.dark.withOpacity(.9),
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),
                          const Divider(height: 1),

                          // ───────────── 상단 설명 + 하단 작업 카드 레이아웃 ─────────────
                          Expanded(
                            child: Column(
                              children: [
                                // ⬆ 상단 설명/정보 영역 (스크롤)
                                Expanded(
                                  flex: 5,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 1) 출근조 안내 섹션 (카드 형태)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: _Palette.light.withOpacity(0.06),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: _Palette.light.withOpacity(0.25),
                                            ),
                                          ),
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
                                                  Icons.info_outline,
                                                  color: _Palette.fg,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '출근조 안내',
                                                      style: textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                        color: _Palette.dark.withOpacity(0.95),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '출근자의 핸드폰에 저장된 입차 완료 차량 내역을\n'
                                                          '같은 지역에서 근무하는 사용자에게 한 번에 공유하는 기능입니다.',
                                                      style: textTheme.bodySmall?.copyWith(
                                                        color: cs.onSurface.withOpacity(0.8),
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(height: 16),

                                        // 2) 현재 컨텍스트 정보 (roomId / 이름)
                                        Container(
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
                                                    const Text('내 이름: '),
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

                                        const SizedBox(height: 16),

                                        // 3) 퇴근조 안내 (수신자용 카드)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: _Palette.light.withOpacity(0.06),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: _Palette.light.withOpacity(0.25),
                                            ),
                                          ),
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
                                                  Icons.info_outline,
                                                  color: _Palette.fg,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '퇴근조 안내',
                                                      style: textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                        color: _Palette.dark.withOpacity(0.95),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '마지막 조 근무자는 이 데이터를 기준으로 업무 인수인계를 받고\n'
                                                          '정상적인 업무 마감을 진행할 수 있습니다.',
                                                      style: textTheme.bodySmall?.copyWith(
                                                        color: cs.onSurface.withOpacity(0.8),
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 8),

                                // ⬇ 하단 작업 카드
                                Expanded(
                                  flex: 5,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                    child: _WorkActionCard(
                                      cs: cs,
                                      textTheme: textTheme,
                                      roomId: roomId,
                                      isExporting: isExporting,
                                      isImporting: isImporting,
                                      lastError: lastError,
                                      lastExportedCount: lastExportedCount,
                                      lastImportedCount: lastImportedCount,
                                      onShare: handleShare,
                                      onImport: handleImport,
                                      hasStatus: hasStatus,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    clipBehavior: Clip.antiAlias,
  );
}

/// 하단 "작업" 카드 위젯
/// - 카드 자체는 하단 영역을 가득 채우고 (Expanded로 wrap)
/// - 내부에서 두 버튼이 5:5 세로 비율로 배치되도록 구성
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
          // 카드 타이틀
          Text(
            '작업',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          // 버튼 영역: 세로로 5:5로 배분
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 5
                Expanded(
                  flex: 5,
                  child: ElevatedButton.icon(
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
                ),

                const SizedBox(height: 16),

                // 5
                Expanded(
                  flex: 5,
                  child: OutlinedButton.icon(
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
                ),
              ],
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
