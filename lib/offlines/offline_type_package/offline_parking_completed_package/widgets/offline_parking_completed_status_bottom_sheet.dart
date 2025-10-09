// lib/offlines/offline_type_package/offline_parking_completed_package/widgets/offline_parking_completed_status_bottom_sheet.dart

import 'dart:convert';
import 'package:flutter/material.dart';

// ▼ SQLite / 세션 (경로는 프로젝트 구조에 맞게 조정하세요)
import '../../../sql/offline_auth_db.dart';
import '../../../sql/offline_auth_service.dart';

import '../../../../utils/snackbar_helper.dart';
import '../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import '../../../../screens/log_package/log_viewer_bottom_sheet.dart';

// 상태 키 상수 (PlateType 의존 제거)
const String _kStatusParkingRequests  = 'parkingRequests';
const String _kStatusDepartureRequests = 'departureRequests';

Future<void> showOfflineParkingCompletedStatusBottomSheet({
  required BuildContext context,
  required int plateId,
  required Future<void> Function() onRequestEntry,
  required VoidCallback onDelete,
}) async {
  final division = await _loadDivisionFromAccounts();      // ✅ division을 SQLite에서
  final area = await _loadCurrentArea();                   // ✅ area도 SQLite에서

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 1,
      child: _FullHeightSheetSqlite(
        plateId: plateId,
        division: division,
        area: area,
        onRequestEntry: onRequestEntry,
        onDelete: onDelete,
      ),
    ),
  );
}

Future<String> _loadDivisionFromAccounts() async {
  final db = await OfflineAuthDb.instance.database;
  final s = await OfflineAuthService.instance.currentSession();
  final uid = (s?.userId ?? '').trim();

  Map<String, Object?>? row;
  if (uid.isNotEmpty) {
    final r1 = await db.query(
      OfflineAuthDb.tableAccounts,
      columns: const ['division'],
      where: 'userId = ?',
      whereArgs: [uid],
      limit: 1,
    );
    if (r1.isNotEmpty) row = r1.first;
  }
  row ??= (await db.query(
    OfflineAuthDb.tableAccounts,
    columns: const ['division'],
    where: 'isSelected = 1',
    limit: 1,
  )).firstOrNull;

  return ((row?['division'] as String?) ?? '').trim();
}

/// 현재 세션의 area (없으면 isSelected=1 폴백)
Future<String> _loadCurrentArea() async {
  final db = await OfflineAuthDb.instance.database;
  final s = await OfflineAuthService.instance.currentSession();
  final uid = (s?.userId ?? '').trim();

  Map<String, Object?>? row;
  if (uid.isNotEmpty) {
    final r1 = await db.query(
      OfflineAuthDb.tableAccounts,
      columns: const ['currentArea', 'selectedArea'],
      where: 'userId = ?',
      whereArgs: [uid],
      limit: 1,
    );
    if (r1.isNotEmpty) row = r1.first;
  }
  row ??= (await db.query(
    OfflineAuthDb.tableAccounts,
    columns: const ['currentArea', 'selectedArea'],
    where: 'isSelected = 1',
    limit: 1,
  )).firstOrNull;

  return ((row?['currentArea'] as String?) ?? (row?['selectedArea'] as String?) ?? '').trim();
}

class _FullHeightSheetSqlite extends StatefulWidget {
  const _FullHeightSheetSqlite({
    required this.plateId,
    required this.division,
    required this.area,
    required this.onRequestEntry,
    required this.onDelete,
  });

  final int plateId;
  final String division;
  final String area;
  final Future<void> Function() onRequestEntry;
  final VoidCallback onDelete;

  @override
  State<_FullHeightSheetSqlite> createState() => _FullHeightSheetSqliteState();
}

class _FullHeightSheetSqliteState extends State<_FullHeightSheetSqlite> {
  Map<String, Object?>? _plate;
  bool _loading = true;

  String _uid = '';
  String _uname = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await OfflineAuthService.instance.currentSession();
    _uid = (s?.userId ?? '').trim();
    _uname = (s?.name ?? '').trim();
    await _reloadPlate();
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  String _asStr(Object? v) => (v?.toString() ?? '').trim();
  int _asInt(Object? v) => switch (v) {
    int i => i,
    num n => n.toInt(),
    String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  Future<void> _reloadPlate() async {
    setState(() => _loading = true);
    try {
      final db = await OfflineAuthDb.instance.database;
      final rows = await db.query(
        OfflineAuthDb.tablePlates,
        where: 'id = ?',
        whereArgs: [widget.plateId],
        limit: 1,
      );
      setState(() {
        _plate = rows.isNotEmpty ? rows.first : null;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      showFailedSnackbar(context, '데이터를 불러오지 못했습니다: $e');
    }
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

  DateTime _resolveRequestTime(Map<String, Object?> p) {
    final rt = _asStr(p['request_time']);
    if (rt.isNotEmpty) {
      final parsed = DateTime.tryParse(rt);
      if (parsed != null) return parsed;
      final asInt = int.tryParse(rt);
      if (asInt != null && asInt > 0) {
        return DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true).toLocal();
      }
    }
    final updated = _asInt(p['updated_at']);
    final created = _asInt(p['created_at']);
    final ms = updated > 0 ? updated : created;
    if (ms > 0) return DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.now();
  }

  Future<void> _lockPrebill() async {
    final p = _plate;
    if (p == null) return;

    final billingType = _asStr(p['billing_type']);
    if (billingType.isEmpty) {
      showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
      return;
    }

    final entrySec = _resolveRequestTime(p).toUtc().millisecondsSinceEpoch ~/ 1000;
    final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    final result = await showOnTapBillingBottomSheet(
      context: context,
      entryTimeInSeconds: entrySec,
      currentTimeInSeconds: nowSec,
      basicStandard: _asInt(p['basic_standard']),
      basicAmount: _asInt(p['basic_amount']),
      addStandard: _asInt(p['add_standard']),
      addAmount: _asInt(p['add_amount']),
      billingType: billingType.isNotEmpty ? billingType : '변동',
      regularAmount: _asInt(p['regular_amount']),
      regularDurationHours: _asInt(p['regular_duration_hours']),
    );
    if (result == null) return;

    final db = await OfflineAuthDb.instance.database;

    // ⬇️ 여기부터 수정
    final String pm = result.paymentMethod;   // non-nullable
    final String? rn = result.reason;         // nullable

    await db.update(
      OfflineAuthDb.tablePlates,
      {
        'is_locked_fee': 1,
        'locked_fee_amount': result.lockedFee,
        'locked_at_seconds': nowSec,
        'updated_at': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [widget.plateId],
    );

    // reason은 nullable, paymentMethod는 non-nullable
    final trimmedReason = rn?.trim();
    await _appendLog(widget.plateId, {
      'action': '사전 정산',
      'performedBy': _uname.isNotEmpty ? _uname : _uid,
      'timestamp': DateTime.now().toIso8601String(),
      'lockedFee': result.lockedFee,
      if (pm.trim().isNotEmpty) 'paymentMethod': pm,
      if (trimmedReason != null && trimmedReason.isNotEmpty) 'reason': trimmedReason,
    });

    if (!mounted) return;
    await _reloadPlate();

    // ⬇️ 여기도 수정 (null 체크 제거)
    final pmSuffix = pm.trim().isNotEmpty ? ' ($pm)' : '';
    showSuccessSnackbar(context, '사전 정산 완료: ₩${result.lockedFee}$pmSuffix');
  }


  Future<void> _unlockPrebill() async {
    final p = _plate;
    if (p == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => const ConfirmCancelFeeDialog(),
    );
    if (confirm != true) return;

    final db = await OfflineAuthDb.instance.database;
    await db.update(
      OfflineAuthDb.tablePlates,
      {
        'is_locked_fee': 0,
        'locked_fee_amount': null,
        'locked_at_seconds': null,
        'updated_at': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [widget.plateId],
    );

    await _appendLog(widget.plateId, {
      'action': '사전 정산 취소',
      'performedBy': _uname.isNotEmpty ? _uname : _uid,
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;
    await _reloadPlate();
    showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
  }

  Future<void> _moveToDepartureRequest() async {
    final db = await OfflineAuthDb.instance.database;
    await db.update(
      OfflineAuthDb.tablePlates,
      {
        'status_type': _kStatusDepartureRequests,
        'is_selected': 0,
        'updated_at': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [widget.plateId],
    );

    await _appendLog(widget.plateId, {
      'action': '출차 요청으로 이동',
      'performedBy': _uname.isNotEmpty ? _uname : _uid,
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _goBackToParkingRequest() async {
    final db = await OfflineAuthDb.instance.database;
    await db.update(
      OfflineAuthDb.tablePlates,
      {
        'status_type': _kStatusParkingRequests,
        'location': '미지정',
        'is_selected': 0,
        'updated_at': _nowMs(),
      },
      where: 'id = ?',
      whereArgs: [widget.plateId],
    );

    await _appendLog(widget.plateId, {
      'action': '입차 요청으로 되돌리기',
      'performedBy': _uname.isNotEmpty ? _uname : _uid,
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = _plate;
    final locked = ((p?['is_locked_fee'] as int?) ?? 0) != 0;
    final plateNumber = _asStr(p?['plate_number']);

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: _loading || p == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const Row(
              children: [
                Icon(Icons.settings, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text(
                  '입차 완료 상태 처리',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text("정산(사전 정산)"),
              onPressed: locked ? null : _lockPrebill,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.lock_open),
              label: const Text("정산 취소"),
              onPressed: locked ? _unlockPrebill : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.grey.shade100,
                foregroundColor: Colors.black87,
                elevation: 0,
                side: const BorderSide(color: Colors.black12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.exit_to_app),
              label: const Text("출차 요청으로 이동"),
              onPressed: _moveToDepartureRequest,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text("로그 확인"),
              onPressed: () {
                final reqTime = _resolveRequestTime(p);
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LogViewerBottomSheet(
                      initialPlateNumber: plateNumber,
                      division: widget.division,
                      area: widget.area,
                      requestTime: reqTime,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.grey.shade100,
                foregroundColor: Colors.black87,
                elevation: 0,
                side: const BorderSide(color: Colors.black12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.assignment_return),
              label: const Text("입차 요청으로 되돌리기"),
              onPressed: _goBackToParkingRequest,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.orange.shade400,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text("삭제", style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.pop(context);
                widget.onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}
