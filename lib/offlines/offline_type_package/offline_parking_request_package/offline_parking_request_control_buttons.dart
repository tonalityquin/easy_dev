import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../widgets/dialog/confirm_cancel_fee_dialog.dart';

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
  // JSON logs(Text) append
  // ─────────────────────────────────────────────────────────────
  String _appendLogText(String? logsText, Map<String, Object?> log) {
    try {
      final List<dynamic> arr = (logsText == null || logsText.trim().isEmpty)
          ? <dynamic>[]
          : (jsonDecode(logsText) as List<dynamic>);
      arr.add(log);
      return jsonEncode(arr);
    } catch (_) {
      // 파싱 실패 시 새 배열로 시작
      return jsonEncode([log]);
    }
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
  // 사전정산(잠금/해제) SQLite 처리
  // ─────────────────────────────────────────────────────────────
  Future<void> _handleBillingActionSqlite(BuildContext context) async {
    final db = await OfflineAuthDb.instance.database;
    final (uid, uname) = await _currentIdentity();

    final row = await _getSelectedPlateRow();
    if (row == null) {
      showFailedSnackbar(context, '선택된 입차 요청이 없습니다.');
      return;
    }

    final String plateNumber = (row['plate_number'] as String?) ?? '';
    final String area = (row['area'] as String?) ?? '';
    final String billingType = (row['billing_type'] as String?)?.trim() ?? '';
    final int basicAmount = (row['basic_amount'] as int?) ?? 0;
    final int basicStd = (row['basic_standard'] as int?) ?? 0;
    final int addAmount = (row['add_amount'] as int?) ?? 0;
    final int addStd = (row['add_standard'] as int?) ?? 0;
    final int? regularAmount = row['regular_amount'] as int?;
    final int? regularHours = row['regular_duration_hours'] as int?;

    final bool isLockedFee = ((row['is_locked_fee'] as int?) ?? 0) != 0;

    // request_time TEXT, created_at INTEGER(ms)
    int entryTimeSeconds = () {
      final reqText = row['request_time'] as String?;
      if (reqText != null && reqText.trim().isNotEmpty) {
        final dt = DateTime.tryParse(reqText);
        if (dt != null) return dt.toUtc().millisecondsSinceEpoch ~/ 1000;
      }
      final createdMs = (row['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
      return DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: false)
          .toUtc()
          .millisecondsSinceEpoch ~/
          1000;
    }();

    final now = DateTime.now();
    final int currentSeconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;

    // 0원 자동잠금 규칙
    final bool isFixed = billingType == '고정';
    final bool isZeroAutoLock =
        ((basicAmount == 0) && (addAmount == 0)) || (isFixed && (regularAmount ?? 0) == 0);

    // 0원 + 이미 잠금 → 해제 금지
    if (isZeroAutoLock && isLockedFee) {
      showFailedSnackbar(context, '이 차량은 0원 규칙으로 잠금 상태이며 해제할 수 없습니다.');
      return;
    }

    // 0원 + 아직 잠금 아님 → 자동 잠금
    if (isZeroAutoLock && !isLockedFee) {
      final oldLogs = row['logs'] as String?;
      final newLogs = _appendLogText(oldLogs, {
        'action': '사전 정산(자동 잠금: 0원)',
        'performedBy': uname,
        'timestamp': now.toIso8601String(),
        'lockedFee': 0,
        'auto': true,
      });

      await db.update(
        OfflineAuthDb.tablePlates,
        {
          'is_locked_fee': 1,
          'locked_at_seconds': currentSeconds,
          'locked_fee_amount': 0,
          // 선택 해제
          'is_selected': 0,
          'selected_by': null,
          'user_name': uname, // 선택 흔적 정리(유지 여부는 정책에 맞게)
          'logs': newLogs,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: '''
          COALESCE(status_type,'') = ? AND plate_number = ? AND area = ?
          AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
        ''',
        whereArgs: ['parkingRequests', plateNumber, area, uid, uname],
      );

      HapticFeedback.mediumImpact();
      showSuccessSnackbar(context, '0원 유형이라 자동으로 잠금되었습니다.');
      return;
    }

    // 정산 타입 미지정
    if (billingType.isEmpty) {
      showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
      return;
    }

    // 이미 잠금 → 해제(사전 정산 취소)
    if (isLockedFee) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => const ConfirmCancelFeeDialog(),
      );
      if (confirm != true) return;

      final oldLogs = row['logs'] as String?;
      final newLogs = _appendLogText(oldLogs, {
        'action': '사전 정산 취소',
        'performedBy': uname,
        'timestamp': now.toIso8601String(),
      });

      await db.update(
        OfflineAuthDb.tablePlates,
        {
          'is_locked_fee': 0,
          'locked_at_seconds': null,
          'locked_fee_amount': null,
          // 선택 해제
          'is_selected': 0,
          'selected_by': null,
          'user_name': uname,
          'logs': newLogs,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: '''
          COALESCE(status_type,'') = ? AND plate_number = ? AND area = ?
          AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
        ''',
        whereArgs: ['parkingRequests', plateNumber, area, uid, uname],
      );

      HapticFeedback.mediumImpact();
      showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
      return;
    }

    // 잠금 아님 → 바텀시트 열어 사전 정산
    final result = await showOnTapBillingBottomSheet(
      context: context,
      entryTimeInSeconds: entryTimeSeconds,
      currentTimeInSeconds: currentSeconds,
      basicStandard: basicStd,
      basicAmount: basicAmount,
      addStandard: addStd,
      addAmount: addAmount,
      billingType: billingType.isEmpty ? '변동' : billingType,
      regularAmount: regularAmount,
      regularDurationHours: regularHours,
    );
    if (result == null) return;

    final oldLogs = row['logs'] as String?;
    final newLogs = _appendLogText(oldLogs, {
      'action': '사전 정산',
      'performedBy': uname,
      'timestamp': now.toIso8601String(),
      'lockedFee': result.lockedFee,
      'paymentMethod': result.paymentMethod,
      if ((result.reason ?? '').trim().isNotEmpty) 'reason': result.reason!.trim(),
    });

    await db.update(
      OfflineAuthDb.tablePlates,
      {
        'is_locked_fee': 1,
        'locked_at_seconds': currentSeconds,
        'locked_fee_amount': result.lockedFee,
        // 선택 해제
        'is_selected': 0,
        'selected_by': null,
        'user_name': uname,
        'logs': newLogs,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: '''
        COALESCE(status_type,'') = ? AND plate_number = ? AND area = ?
        AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
      ''',
      whereArgs: ['parkingRequests', plateNumber, area, uid, uname],
    );

    HapticFeedback.mediumImpact();
    showSuccessSnackbar(
      context,
      '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
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
                await _handleBillingActionSqlite(context);
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
