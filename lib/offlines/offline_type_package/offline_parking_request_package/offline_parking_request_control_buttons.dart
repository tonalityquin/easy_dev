import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback

import '../../../utils/snackbar_helper.dart';

// ▼ SQLite
import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 계열) + 대비 강조 색
class _Palette {
  static const base = Color(0xFF0D47A1); // primary (Deep Blue)
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const success = Color(0xFF2E7D32); // 입차(완료)용 - Green 800
  static const accent = Color(0xFFFF6D00); // 검색 액션용 - Orange 800
}

class OfflineParkingRequestControlButtons extends StatelessWidget {
  final bool isSorted;
  final bool isLocked;
  final VoidCallback onSearchPressed;
  final VoidCallback onSortToggle;
  final VoidCallback onParkingCompleted;
  final VoidCallback onToggleLock;

  const OfflineParkingRequestControlButtons({
    super.key,
    required this.isSorted,
    required this.isLocked,
    required this.onSearchPressed,
    required this.onSortToggle,
    required this.onParkingCompleted,
    required this.onToggleLock,
  });

  // ─────────────────────────────────────────────────────────────
  // 유틸: 현재 사용자 식별자
  // ─────────────────────────────────────────────────────────────
  Future<(String uid, String uname)> _currentIdentity() async {
    final s = await OfflineAuthService.instance.currentSession();
    final uid = (s?.userId ?? '').trim();
    final uname = (s?.name ?? '').trim();
    return (uid, uname);
  }

  // ─────────────────────────────────────────────────────────────
  // 유틸: 선택된 입차요청 1건 조회 (현재 사용자 범위)
  // ─────────────────────────────────────────────────────────────
  Future<Map<String, Object?>?> _getSelectedPlateRow() async {
    final db = await OfflineAuthDb.instance.database;
    final (uid, uname) = await _currentIdentity();

    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const [
        'id',
        'plate_number',
        'area',
        'location',
        'billing_type',
        'basic_amount',
        'basic_standard',
        'add_amount',
        'add_standard',
        'regular_amount',
        'regular_duration_hours',
        'is_locked_fee',
        'locked_fee_amount',
        'locked_at_seconds',
        'is_selected',
        'selected_by',
        'user_name',
        'status_type',
        'request_time',
        'created_at',
        'logs',
      ],
      where: '''
        is_selected = 1
        AND COALESCE(status_type,'') = ?
        AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
      ''',
      whereArgs: ['parkingRequests', uid, uname],
      orderBy: 'COALESCE(updated_at, created_at) DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  // 현재 사용자 기준 선택 차량 존재 여부
  Future<bool> _hasSelectedPlate() async {
    final row = await _getSelectedPlateRow();
    return row != null && ((row['is_selected'] as int? ?? 0) != 0);
  }

  // ─────────────────────────────────────────────────────────────
  // 상태 바텀시트 (입차 요청 취소)
  // ─────────────────────────────────────────────────────────────
  Future<void> _showStatusBottomSheet(BuildContext context) async {
    final selected = await _getSelectedPlateRow();
    if (selected == null) {
      showFailedSnackbar(context, '선택된 입차 요청이 없습니다.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '상태 수정',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),

                // ⬇️ 추가된 항목 (동작 없음: 비활성화 표시)
                const ListTile(
                  leading: Icon(Icons.receipt_long),
                  title: Text('로그 확인'),
                  enabled: false, // 기능 없이 비활성화
                ),
                const ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('정보 수정'),
                  enabled: false, // 기능 없이 비활성화
                ),
                const Divider(),

                // 기존: 입차 요청 취소
                ListTile(
                  leading: const Icon(Icons.cancel),
                  title: const Text('입차 요청 취소'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _cancelEntryRequestSqlite(context, selected);
                  },
                ),

                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('닫기'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _cancelEntryRequestSqlite(
    BuildContext context,
    Map<String, Object?> selected,
  ) async {
    try {
      final db = await OfflineAuthDb.instance.database;
      final id = selected['id'] as int;
      await db.delete(
        OfflineAuthDb.tablePlates,
        where: 'id = ? AND COALESCE(status_type, "") = ?',
        whereArgs: [id, 'parkingRequests'],
      );

      HapticFeedback.mediumImpact();
      showSuccessSnackbar(context, '입차 요청이 취소되었습니다: ${selected['plate_number'] ?? ''}');
    } catch (e, st) {
      debugPrint('cancel entry request error: $e\n$st');
      showFailedSnackbar(context, '입차 요청 취소 중 오류가 발생했습니다.');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // [NEW] 정산 안내 풀스크린 바텀시트
  // 핸드폰 최상단까지 올라오는 형태 + 안내 문구 출력
  // '정산 진행'을 누르면 기존 사전정산 로직(_handleBillingActionSqlite) 실행
  // ─────────────────────────────────────────────────────────────
  Future<void> _showBillingInfoFullSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // ✅ 최상단까지
      useSafeArea: true,
      // ✅ 노치/상단 안전영역 반영
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 1, // ✅ 화면 전체 높이
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '정산 관리',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        tooltip: '닫기',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '기본 정산, 할증, 할인을 적용할 수 있습니다.',
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // (하단 버튼 제거) - 필요시 설명/옵션 영역을 여기에 추가하세요.
                  // Expanded(child: SingleChildScrollView(child: ...)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color selectedItemColor = _Palette.base;
    final Color unselectedItemColor = _Palette.dark.withOpacity(.55);
    final Color muted = _Palette.dark.withOpacity(.60);

    return FutureBuilder<bool>(
      future: _hasSelectedPlate(),
      builder: (context, snap) {
        final isPlateSelected = snap.data == true;

        return BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          iconSize: 24,
          selectedItemColor: selectedItemColor,
          unselectedItemColor: unselectedItemColor,
          items: [
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '정산 관리' : '화면 잠금',
                child: Icon(
                  isPlateSelected ? Icons.payments : (isLocked ? Icons.lock : Icons.lock_open),
                  color: isPlateSelected ? _Palette.base : muted,
                ),
              ),
              label: isPlateSelected ? '정산 관리' : '화면 잠금',
            ),
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '입차 완료' : '번호판 검색',
                child: isPlateSelected
                    ? const Icon(Icons.check_circle, color: _Palette.success)
                    : const Icon(Icons.search, color: _Palette.accent),
              ),
              label: isPlateSelected ? '입차' : '번호판 검색',
            ),
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '상태 수정' : '정렬 변경',
                child: AnimatedRotation(
                  turns: isSorted ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Transform.scale(
                    scaleX: isSorted ? -1 : 1,
                    child: Icon(
                      isPlateSelected ? Icons.settings : Icons.sort,
                      color: muted,
                    ),
                  ),
                ),
              ),
              label: isPlateSelected ? '상태 수정' : (isSorted ? '최신순' : '오래된순'),
            ),
          ],
          onTap: (index) async {
            HapticFeedback.selectionClick();

            if (index == 0) {
              final hasSel = await _hasSelectedPlate();
              if (hasSel) {
                // ✅ 변경: 바로 정산 로직 실행 대신, 최상단까지 올라오는 안내 바텀시트 먼저 노출
                await _showBillingInfoFullSheet(context);
              } else {
                onToggleLock();
              }
            } else if (index == 1) {
              final hasSel = await _hasSelectedPlate();
              if (hasSel) {
                onParkingCompleted();
              } else {
                onSearchPressed();
              }
            } else if (index == 2) {
              final hasSel = await _hasSelectedPlate();
              if (hasSel) {
                await _showStatusBottomSheet(context);
              } else {
                onSortToggle();
              }
            }
          },
        );
      },
    );
  }
}
