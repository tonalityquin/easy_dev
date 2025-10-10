// lib/offlines/offline_type_package/offline_parking_completed_package/offline_parking_completed_control_buttons.dart
//
// 변경 요약 👇
// - Firestore/Provider/Repository/PlateType/UserState/PlateState/DeletePlate 완전 제거
// - SQLite만 사용하여 선택된 차량 조회/사전정산/정산취소/출차요청 준비/삭제 처리
// - 로그는 offline_plates.logs(TEXT)에 JSON 배열 문자열로 축적
// - '상태 수정' 탭은 간단 액션 시트(입차요청/삭제)로 대체
//
// 스키마 참고(offline_plates):
// id INTEGER PK, plate_number TEXT, plate_four_digit TEXT, area TEXT, location TEXT,
// basic_amount INTEGER, add_amount INTEGER, basic_standard INTEGER, add_standard INTEGER,
// is_locked_fee INTEGER, locked_fee_amount INTEGER, locked_at_seconds INTEGER,
// status_type TEXT, request_time TEXT, updated_at INTEGER, created_at INTEGER,
// billing_type TEXT, regular_amount INTEGER, regular_duration_hours INTEGER,
// selected_by TEXT, user_name TEXT, is_selected INTEGER, logs TEXT
//
import 'dart:convert';

import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

import '../../../utils/snackbar_helper.dart';

// 기존 UI 구성요소 (그대로 사용)
import '../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../offline_departure_completed_bottom_sheet.dart';

// 상태시트는 간단 액션시트로 대체 → 기존 import 제거
import 'widgets/offline_set_departure_request_dialog.dart';
import '../../../widgets/dialog/plate_remove_dialog.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 계열) + 상태 색상
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘

  // 상태 강조 색
  static const danger = Color(0xFFD32F2F); // 출차 요청(붉은색)
  static const success = Color(0xFF2E7D32); // 출차 완료(초록색)
}

// PlateType 의존 제거: status_type 문자열 키 상수
const String _kStatusParkingCompleted = 'parkingCompleted';

class OfflineParkingCompletedControlButtons extends StatefulWidget {
  final bool isParkingAreaMode;
  final bool isStatusMode;
  final bool isLocationPickerMode;
  final bool isSorted;
  final bool isLocked;
  final VoidCallback onToggleLock;
  final VoidCallback showSearchDialog;
  final VoidCallback resetParkingAreaFilter;
  final VoidCallback toggleSortIcon;

  // 외부(상위)에서 구현한 콜백(오프라인 SQLite 버전에도 그대로 사용)
  final Function(BuildContext context, String plateNumber, String area) handleEntryParkingRequest;
  final Function(BuildContext context) handleDepartureRequested;

  const OfflineParkingCompletedControlButtons({
    super.key,
    required this.isParkingAreaMode,
    required this.isStatusMode,
    required this.isLocationPickerMode,
    required this.isSorted,
    required this.isLocked,
    required this.onToggleLock,
    required this.showSearchDialog,
    required this.resetParkingAreaFilter,
    required this.toggleSortIcon,
    required this.handleEntryParkingRequest,
    required this.handleDepartureRequested,
  });

  @override
  State<OfflineParkingCompletedControlButtons> createState() => _OfflineParkingCompletedControlButtonsState();
}

class _OfflineParkingCompletedControlButtonsState extends State<OfflineParkingCompletedControlButtons> {
  // 현재 세션 아이덴티티
  String _uid = '';
  String _uname = '';

  // 선택된 plate (간이 맵)
  Map<String, Object?>? _selectedPlate;

  @override
  void initState() {
    super.initState();
    _initSession().then((_) => _reloadSelectedPlate());
  }

  Future<void> _initSession() async {
    final s = await OfflineAuthService.instance.currentSession();
    _uid = (s?.userId ?? '').trim();
    _uname = (s?.name ?? '').trim();
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  // 선택된 plate 1건 로드 (나의 선택)
  Future<void> _reloadSelectedPlate() async {
    final db = await OfflineAuthDb.instance.database;
    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const [
        'id',
        'plate_number',
        'area',
        'basic_amount',
        'add_amount',
        'basic_standard',
        'add_standard',
        'billing_type',
        'regular_amount',
        'regular_duration_hours',
        'is_locked_fee',
        'locked_fee_amount',
        'locked_at_seconds',
        'request_time',
        'updated_at',
        'created_at',
        'is_selected',
        'logs',
      ],
      where: '''
        is_selected = 1
        AND COALESCE(status_type,'') = ?
        AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
      ''',
      whereArgs: [_kStatusParkingCompleted, _uid, _uname],
      orderBy: 'COALESCE(updated_at, created_at) DESC',
      limit: 1,
    );

    if (!mounted) return; // ← setState after dispose 방지
    setState(() {
      _selectedPlate = rows.isNotEmpty ? rows.first : null;
    });
  }

  bool get _hasSelected => _selectedPlate != null;

  bool _isLockedFee(Map<String, Object?> p) => ((p['is_locked_fee'] as int?) ?? 0) != 0;

  int _asInt(Object? v) => switch (v) {
        int i => i,
        num n => n.toInt(),
        String s => int.tryParse(s) ?? 0,
        _ => 0,
      };

  String _asStr(Object? v) => (v?.toString() ?? '').trim();

  int _entryTimeSecondsOf(Map<String, Object?> p) {
    // request_time(TEXT) → seconds, 없으면 updated_at/created_at(ms)
    final rt = _asStr(p['request_time']);
    if (rt.isNotEmpty) {
      final dt = DateTime.tryParse(rt);
      if (dt != null) return dt.toUtc().millisecondsSinceEpoch ~/ 1000;
      final asInt = int.tryParse(rt); // 혹시 epoch seconds 문자열이면
      if (asInt != null && asInt > 0) return asInt;
    }
    final updated = _asInt(p['updated_at']);
    final created = _asInt(p['created_at']);
    final ms = updated > 0 ? updated : created;
    return ms > 0 ? (ms ~/ 1000) : (DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }

  Future<void> _appendLog(int id, Map<String, Object?> log) async {
    final db = await OfflineAuthDb.instance.database;
    final r = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const ['logs'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    List logs = [];
    if (r.isNotEmpty) {
      final raw = _asStr(r.first['logs']);
      if (raw.isNotEmpty) {
        try {
          final parsed = jsonDecode(raw);
          if (parsed is List) logs = parsed;
        } catch (_) {}
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

  Future<void> _autoLockZeroFee(Map<String, Object?> p) async {
    // 0원 규칙: basic==0 && add==0 이고 아직 잠금 아님 → 자동 잠금
    final id = _asInt(p['id']);
    final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    final db = await OfflineAuthDb.instance.database;
    await db.update(
      OfflineAuthDb.tablePlates,
      {
        'is_locked_fee': 1,
        'locked_fee_amount': 0,
        'locked_at_seconds': nowSec,
        'updated_at': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    await _appendLog(id, {
      'action': '사전 정산(자동 잠금: 0원)',
      'performedBy': _uname.isNotEmpty ? _uname : _uid,
      'timestamp': DateTime.now().toIso8601String(),
      'lockedFee': 0,
      'auto': true,
    });

    showSuccessSnackbar(context, '0원 유형이라 자동으로 잠금되었습니다.');
  }

  Future<void> _lockWithBilling(Map<String, Object?> p) async {
    // 바텀시트로 금액/결제수단 입력받아 잠금
    final id = _asInt(p['id']);
    final entrySec = _entryTimeSecondsOf(p);
    final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    final result = await showOnTapBillingBottomSheet(
      context: context,
      entryTimeInSeconds: entrySec,
      currentTimeInSeconds: nowSec,
      basicStandard: _asInt(p['basic_standard']),
      basicAmount: _asInt(p['basic_amount']),
      addStandard: _asInt(p['add_standard']),
      addAmount: _asInt(p['add_amount']),
      billingType: _asStr(p['billing_type']).isNotEmpty ? _asStr(p['billing_type']) : '변동',
      regularAmount: _asInt(p['regular_amount']),
      regularDurationHours: _asInt(p['regular_duration_hours']),
    );
    if (result == null) return;

    final db = await OfflineAuthDb.instance.database;
    await db.update(
      OfflineAuthDb.tablePlates,
      {
        'is_locked_fee': 1,
        'locked_fee_amount': result.lockedFee,
        'locked_at_seconds': nowSec,
        'updated_at': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    final pm = _asStr(result.paymentMethod);
    final rsn = _asStr(result.reason);

    await _appendLog(id, {
      'action': '사전 정산',
      'performedBy': _uname.isNotEmpty ? _uname : _uid,
      'timestamp': DateTime.now().toIso8601String(),
      'lockedFee': result.lockedFee,
      if (pm.isNotEmpty) 'paymentMethod': pm,
      if (rsn.isNotEmpty) 'reason': rsn,
    });

    showSuccessSnackbar(
      context,
      '사전 정산 완료: ₩${result.lockedFee}${pm.isNotEmpty ? ' ($pm)' : ''}',
    );
  }

  Future<void> _deleteFromParkingCompleted({
    required String plateNumber,
    required String area,
  }) async {
    final db = await OfflineAuthDb.instance.database;
    final n = await db.delete(
      OfflineAuthDb.tablePlates,
      where: '''
        plate_number = ? AND area = ? AND COALESCE(status_type,'') = ?
      ''',
      whereArgs: [plateNumber.trim(), area.trim(), _kStatusParkingCompleted],
    );
    if (n > 0) {
      showSuccessSnackbar(context, '삭제 완료: $plateNumber');
    } else {
      showFailedSnackbar(context, '삭제 대상이 없거나 이미 삭제되었습니다.');
    }
    await _reloadSelectedPlate();
  }

  // '상태 수정' 대체: 간단 액션 시트
  Future<void> _showSimpleStatusSheet(Map<String, Object?> p) async {
    final pn = _asStr(p['plate_number']);
    final area = _asStr(p['area']);

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.1),
                  blurRadius: 12,
                )
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('입차 요청으로 상태 변경'),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.handleEntryParkingRequest(context, pn, area);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: _Palette.danger),
                  title: const Text('삭제'),
                  onTap: () {
                    Navigator.of(context).pop();
                    showDialog(
                      context: context,
                      builder: (_) => PlateRemoveDialog(
                        onConfirm: () => _deleteFromParkingCompleted(
                          plateNumber: pn,
                          area: area,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 팔레트 기반 컬러
    final Color selectedItemColor = _Palette.base;
    final Color unselectedItemColor = _Palette.dark.withOpacity(.55);
    final Color muted = _Palette.dark.withOpacity(.60);

    final bool isPlateSelected = _hasSelected;

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      elevation: 0,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      iconSize: 24,
      selectedItemColor: selectedItemColor,
      unselectedItemColor: unselectedItemColor,
      items: (widget.isLocationPickerMode || widget.isStatusMode)
          ? const [
              BottomNavigationBarItem(
                icon: Icon(Icons.lock), // AnimatedSwitcher는 간소화
                label: '잠금',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.move_down, color: _Palette.danger),
                label: '출차 요청',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.directions_car, color: _Palette.success),
                label: '출차 완료',
              ),
            ]
          : [
              BottomNavigationBarItem(
                icon: isPlateSelected
                    ? (_isLockedFee(_selectedPlate!)
                        ? const Icon(Icons.lock, key: ValueKey('lock'), color: Color(0x9909367D))
                        : const Icon(Icons.lock_open, key: ValueKey('unlock'), color: Color(0x9909367D)))
                    : Icon(Icons.refresh, key: const ValueKey('refresh'), color: muted),
                label: isPlateSelected ? (_isLockedFee(_selectedPlate!) ? '정산 취소' : '사전 정산') : '채팅하기',
              ),
              BottomNavigationBarItem(
                icon: Icon(
                  isPlateSelected ? Icons.check_circle : Icons.search,
                  color: isPlateSelected ? _Palette.danger : muted,
                ),
                label: isPlateSelected ? '출차 요청' : '번호판 검색',
              ),
              BottomNavigationBarItem(
                icon: Transform.scale(
                  scaleX: widget.isSorted ? -1 : 1,
                  child: Icon(
                    isPlateSelected ? Icons.settings : Icons.sort,
                    color: muted,
                  ),
                ),
                label: isPlateSelected ? '상태 수정' : (widget.isSorted ? '최신순' : '오래된 순'),
              ),
            ],
      onTap: (index) async {
        // 상태/로케이션 선택 모드
        if (widget.isLocationPickerMode || widget.isStatusMode) {
          if (index == 0) {
            widget.onToggleLock();
          } else if (index == 1) {
            // '출차 요청' 버튼 → 검색/다이얼로그(현행 유지)
            widget.showSearchDialog();
          } else if (index == 2) {
            // 출차 완료 현황 시트(리팩터링된 바텀시트: selectedDate 필수)
            final now = DateTime.now();
            final selectedDate = DateTime(now.year, now.month, now.day);
            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => OfflineDepartureCompletedBottomSheet(
                selectedDate: selectedDate,
              ),
            );
          }
          return;
        }

        // 일반 모드: 선택 안된 경우
        if (!widget.isParkingAreaMode || !isPlateSelected) {
          if (index == 0 || index == 1) {
            widget.showSearchDialog();
          } else if (index == 2) {
            widget.toggleSortIcon();
          }
          return;
        }

        // 선택된 차량 기준 실행
        final p = _selectedPlate!;
        final basicAmount = _asInt(p['basic_amount']);
        final addAmount = _asInt(p['add_amount']);
        final billingType = _asStr(p['billing_type']);

        if (index == 0) {
          // === 사전 정산 / 정산 취소 ===
          final isZeroZero = (basicAmount == 0) && (addAmount == 0);
          final locked = _isLockedFee(p);

          // 0원 + 이미 잠금 → 해제 금지
          if (isZeroZero && locked) {
            showFailedSnackbar(context, '이 차량은 0원 규칙으로 잠금 상태이며 해제할 수 없습니다.');
            return;
          }

          // 0원 + 아직 잠금 아님 → 자동 잠금
          if (isZeroZero && !locked) {
            await _autoLockZeroFee(p);
            await _reloadSelectedPlate();
            return;
          }

          // 정산 타입 미지정
          if (!locked && billingType.isEmpty) {
            showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
            return;
          }

          if (locked) {
            // 정산 취소 확인
          } else {
            // 사전 정산 바텀시트
            await _lockWithBilling(p);
            await _reloadSelectedPlate();
          }
        } else if (index == 1) {
          // 출차 요청(확정 동작은 상위 콜백에서 SQLite 처리)
          showDialog(
            context: context,
            builder: (context) => OfflineSetDepartureRequestBottomSheet(
              onConfirm: () => widget.handleDepartureRequested(context),
            ),
          );
        } else if (index == 2) {
          // 상태 수정 (간이 액션시트)
          await _showSimpleStatusSheet(p);
          await _reloadSelectedPlate();
        }
      },
    );
  }
}
