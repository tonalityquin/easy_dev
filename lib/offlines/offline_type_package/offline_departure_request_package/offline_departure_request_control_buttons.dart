// lib/screens/type_pages/offline_departure_request_package/departure_request_control_buttons.dart
//
// 변경 요약 👇
// - Firestore/Provider/Repository 제거 → SQLite(offline_auth_db/offline_auth_service)만 사용
// - PlateType/PlateState/PlateModel 의존 제거
// - 현재 선택 차량 여부는 offline_plates에서 is_selected=1 && status_type='departureRequests'
//   && (selected_by=userId OR user_name=name) 로 직접 조회
// - 정산(자동 0원 잠금 / 잠금 취소 / 사전 정산), 출차 완료 트리거 모두 SQLite 처리
// - 상태 시트는 PlateModel 의존 대신, 로컬 간단 액션 시트로 대체(입차요청/입차완료/삭제)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback

// ▼ SQLite / 세션
import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
// 기존 widgets/departure_request_status_bottom_sheet.dart 는 PlateModel 의존 → 사용 제거
import '../../../widgets/dialog/plate_remove_dialog.dart';

/// Deep Blue 팔레트 + 상태 강조 색
class _Palette {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const danger = Color(0xFFD32F2F);
  static const success = Color(0xFF2E7D32);
}

// ⛳ 상태 문자열(PlateType 대체)
const String _kStatusDepartureRequests = 'departureRequests';

class OfflineDepartureRequestControlButtons extends StatefulWidget {
  final bool isSorted;
  final bool isLocked;

  final VoidCallback showSearchDialog;
  final VoidCallback toggleSortIcon;
  final VoidCallback handleDepartureCompleted;
  final VoidCallback toggleLock;

  // 상태 시트에서 사용할 콜백 (페이지에서 주입)
  final Function(BuildContext context, String plateNumber, String area)
  handleEntryParkingRequest;
  final Function(
      BuildContext context,
      String plateNumber,
      String area,
      String location,
      ) handleEntryParkingCompleted;

  const OfflineDepartureRequestControlButtons({
    super.key,
    required this.isSorted,
    required this.isLocked,
    required this.showSearchDialog,
    required this.toggleSortIcon,
    required this.handleDepartureCompleted,
    required this.toggleLock,
    required this.handleEntryParkingRequest,
    required this.handleEntryParkingCompleted,
  });

  @override
  State<OfflineDepartureRequestControlButtons> createState() =>
      _OfflineDepartureRequestControlButtonsState();
}

class _OfflineDepartureRequestControlButtonsState
    extends State<OfflineDepartureRequestControlButtons> {
  Map<String, Object?>? _selectedRow; // 현재 선택된 plate row (offline_plates)
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshSelected(); // 처음/리빌드마다 선택 상태 동기화
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
  int _nowSec() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  Future<(String uid, String uname)> _sessionIdentity() async {
    final s = await OfflineAuthService.instance.currentSession();
    return ((s?.userId ?? '').trim(), (s?.name ?? '').trim());
  }

  Future<void> _refreshSelected() async {
    try {
      setState(() => _loading = true);
      final db = await OfflineAuthDb.instance.database;
      final (uid, uname) = await _sessionIdentity();
      final rows = await db.query(
        OfflineAuthDb.tablePlates,
        where: '''
          is_selected = 1
          AND COALESCE(status_type,'') = ?
          AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
        ''',
        whereArgs: [_kStatusDepartureRequests, uid, uname],
        orderBy: 'COALESCE(updated_at, created_at) DESC',
        limit: 1,
      );
      _selectedRow = rows.isNotEmpty ? rows.first : null;
    } catch (_) {
      _selectedRow = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // logs(JSON Array String) 에 로그 한 건 추가
  Future<void> _appendLog(int id, Map<String, Object?> log) async {
    final db = await OfflineAuthDb.instance.database;
    final r = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const ['logs'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    List<dynamic> logs = [];
    if (r.isNotEmpty) {
      final raw = r.first['logs'];
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          logs = jsonDecode(raw) as List<dynamic>;
        } catch (_) {/* ignore */}
      }
    }
    logs.add(log);
    await db.update(
      OfflineAuthDb.tablePlates,
      {'logs': jsonEncode(logs)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  int _selected_row_int(String key) => (_selectedRow?[key] as int?) ?? 0;

  // 정산 관리(자동 0원 잠금 / 취소 / 사전 정산)
  Future<void> _handleBilling() async {
    if (_selectedRow == null) return;

    final db = await OfflineAuthDb.instance.database;
    final (uid, uname) = await _sessionIdentity();

    final int id = (_selectedRow!['id'] as int);
    final String billingType = (_selectedRow!['billing_type'] as String?)?.trim() ?? '';
    final int basicAmount   = (_selectedRow!['basic_amount'] as int?) ?? 0;
    final int addAmount     = _selected_row_int('add_amount');
    final int? regularAmount = _selectedRow!['regular_amount'] as int?;
    final bool isFixed = billingType == '고정';

    // 자동 0원 잠금 여부
    final bool isZeroAuto = ((basicAmount == 0) && (addAmount == 0)) ||
        (isFixed && ((regularAmount ?? 0) == 0));

    final bool isLockedFee =
        ((_selectedRow!['is_locked_fee'] as int?) ?? 0) != 0;

    final nowIso = DateTime.now().toIso8601String();
    final currentSec = _nowSec();

    // 자동 0원 잠금 해제 불가 규칙
    if (isZeroAuto && isLockedFee) {
      showFailedSnackbar(context, '이 차량은 0원 규칙으로 잠금 상태이며 해제할 수 없습니다.');
      return;
    }

    // 자동 0원 잠금 수행
    if (isZeroAuto && !isLockedFee) {
      await db.update(
        OfflineAuthDb.tablePlates,
        {
          'is_locked_fee': 1,
          'locked_at_seconds': currentSec, // ✅ 스키마 컬럼명
          'locked_fee_amount': 0,
          // 선택 해제 + 수행자 기록
          'is_selected': 0,
          'selected_by': null,
          'user_name': uname,
          'updated_at': _nowMs(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await _appendLog(id, {
        'action': '사전 정산(자동 잠금: 0원)',
        'performedBy': uname,
        'timestamp': nowIso,
        'lockedFee': 0,
        'auto': true,
      });

      HapticFeedback.mediumImpact();
      showSuccessSnackbar(context, '0원 유형이라 자동으로 잠금되었습니다.');
      await _refreshSelected();
      return;
    }

    // 정산 타입 미지정
    if (billingType.isEmpty) {
      showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
      return;
    }

    // 잠금 해제(사전 정산 취소)
    if (isLockedFee) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => const ConfirmCancelFeeDialog(),
      );
      if (confirm != true) return;

      await db.update(
        OfflineAuthDb.tablePlates,
        {
          'is_locked_fee': 0,
          'locked_at_seconds': null,     // ✅ 스키마 컬럼명
          'locked_fee_amount': null,
          // 선택 해제 + 수행자 기록
          'is_selected': 0,
          'selected_by': null,
          'user_name': uname,
          'updated_at': _nowMs(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await _appendLog(id, {
        'action': '사전 정산 취소',
        'performedBy': uname,
        'timestamp': nowIso,
      });

      HapticFeedback.mediumImpact();
      showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
      await _refreshSelected();
      return;
    }

    // 사전 정산(잠금)
    // request_time: TEXT 가능 → 안전 파싱
    final entrySec = () {
      final req = _selectedRow!['request_time'];
      if (req is String && req.trim().isNotEmpty) {
        final dt = DateTime.tryParse(req);
        if (dt != null) return dt.toUtc().millisecondsSinceEpoch ~/ 1000;
      }
      // fallback: created_at(ms)
      final createdMs = (_selectedRow!['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
      return DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: false).toUtc().millisecondsSinceEpoch ~/ 1000;
    }();

    final result = await showOnTapBillingBottomSheet(
      context: context,
      entryTimeInSeconds: entrySec,
      currentTimeInSeconds: currentSec,
      basicStandard: _selected_row_int('basic_standard'),
      basicAmount: basicAmount,
      addStandard: _selected_row_int('add_standard'),
      addAmount: addAmount,
      billingType: billingType.isEmpty ? '변동' : billingType,
      regularAmount: regularAmount,
      regularDurationHours: _selectedRow!['regular_duration_hours'] as int?,
    );
    if (result == null) return;

    await db.update(
      OfflineAuthDb.tablePlates,
      {
        'is_locked_fee': 1,
        'locked_at_seconds': currentSec, // ✅ 스키마 컬럼명
        'locked_fee_amount': result.lockedFee,
        // 선택 해제 + 수행자 기록
        'is_selected': 0,
        'selected_by': null,
        'user_name': uname,
        'updated_at': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    final log = <String, Object?>{
      'action': '사전 정산',
      'performedBy': uname,
      'timestamp': nowIso,
      'lockedFee': result.lockedFee,
      'paymentMethod': result.paymentMethod, // DB에는 저장하지 않고 로그에만 기록
    };
    if ((result.reason ?? '').trim().isNotEmpty) {
      log['reason'] = result.reason!.trim();
    }
    await _appendLog(id, log);

    HapticFeedback.mediumImpact();
    showSuccessSnackbar(
      context,
      '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
    );
    await _refreshSelected();
  }

  // ✅ PlateModel 의존 없는 간단 상태 시트
  Future<void> _showQuickActionsSheet() async {
    if (_selectedRow == null) return;
    final plateNumber = (_selectedRow!['plate_number'] as String?) ?? '';
    final area = (_selectedRow!['area'] as String?) ?? '';
    final location = (_selectedRow!['location'] as String?) ?? '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('입차 요청으로 변경'),
              onTap: () {
                Navigator.pop(context);
                widget.handleEntryParkingRequest(context, plateNumber, area);
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_parking),
              title: const Text('입차 완료 처리'),
              onTap: () {
                Navigator.pop(context);
                widget.handleEntryParkingCompleted(context, plateNumber, area, location);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await showDialog(
                  context: context,
                  builder: (_) => PlateRemoveDialog(
                    onConfirm: () async {
                      final db = await OfflineAuthDb.instance.database;
                      final id = _selectedRow?['id'] as int?;
                      if (id != null) {
                        await db.delete(
                          OfflineAuthDb.tablePlates,
                          where: 'id = ?',
                          whereArgs: [id],
                        );
                        showSuccessSnackbar(context, "삭제 완료: $plateNumber");
                        await _refreshSelected();
                      } else {
                        showFailedSnackbar(context, '삭제할 항목을 찾을 수 없습니다.');
                      }
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color selectedItemColor = _Palette.base;
    final Color unselectedItemColor = _Palette.dark.withOpacity(.55);
    final Color muted = _Palette.dark.withOpacity(.60);

    final bool isPlateSelected =
        !_loading && _selectedRow != null && ((_selectedRow!['is_selected'] as int?) ?? 0) != 0;

    return BottomNavigationBar(
      backgroundColor: Colors.white,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: selectedItemColor,
      unselectedItemColor: unselectedItemColor,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      iconSize: 24,
      items: [
        BottomNavigationBarItem(
          icon: Tooltip(
            message: isPlateSelected ? '정산 관리' : '화면 잠금',
            child: Icon(
              isPlateSelected ? Icons.payments : (widget.isLocked ? Icons.lock : Icons.lock_open),
              color: muted,
            ),
          ),
          label: isPlateSelected ? '정산 관리' : '화면 잠금',
        ),
        BottomNavigationBarItem(
          icon: Tooltip(
            message: isPlateSelected ? '출차 완료' : '번호판 검색',
            child: Icon(
              isPlateSelected ? Icons.check_circle : Icons.search,
              color: isPlateSelected ? _Palette.success : _Palette.danger,
            ),
          ),
          label: isPlateSelected ? '출차' : '검색',
        ),
        BottomNavigationBarItem(
          icon: Tooltip(
            message: isPlateSelected ? '상태 수정' : '정렬 변경',
            child: AnimatedRotation(
              turns: widget.isSorted ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Transform.scale(
                scaleX: widget.isSorted ? -1 : 1,
                child: Icon(
                  isPlateSelected ? Icons.settings : Icons.sort,
                  color: muted,
                ),
              ),
            ),
          ),
          label: isPlateSelected ? '상태 수정' : (widget.isSorted ? '최신순' : '오래된순'),
        ),
      ],
      onTap: (index) async {
        HapticFeedback.selectionClick();

        if (!isPlateSelected) {
          if (index == 0) {
            widget.toggleLock();
          } else if (index == 1) {
            widget.showSearchDialog();
          } else if (index == 2) {
            widget.toggleSortIcon();
          }
          return;
        }

        // 차량 선택됨
        if (index == 0) {
          await _handleBilling();
        } else if (index == 1) {
          // 출차 완료 트리거(실제 상태 전환은 페이지 콜백에서 SQLite로 처리)
          widget.handleDepartureCompleted();
          await _refreshSelected();
        } else if (index == 2) {
          // PlateModel 의존 시트를 대체한 로컬 간단 액션 시트
          await _showQuickActionsSheet();
        }
      },
    );
  }
}
