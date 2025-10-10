// lib/offlines/offline_type_package/offline_parking_completed_package/widgets/offline_parking_completed_status_bottom_sheet.dart
//
// 리팩터링 사항
// - "정산(사전 정산)" 버튼: 로직 제거 및 비활성화(onPressed: null)
// - "로그 확인" 버튼: 로직 제거 및 비활성화(onPressed: null)
// - "정보 수정" 버튼 추가: 비활성화(onPressed: null), "로그 확인" 아래에 배치
// - 정산 취소 로직 삭제 및 버튼 비활성화(onPressed: null)
// - 불필요해진 import 정리(ConfirmCancelFeeDialog 제거). 정산 취소는 비활성화 버튼만 유지.
//

import 'dart:convert';
import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../../../sql/offline_auth_db.dart';
import '../../../sql/offline_auth_service.dart';

import '../../../../utils/snackbar_helper.dart';

// 상태 키 상수
const String _kStatusParkingRequests = 'parkingRequests';
const String _kStatusDepartureRequests = 'departureRequests';

Future<void> showOfflineParkingCompletedStatusBottomSheet({
  required BuildContext context,
  required int plateId,
  required Future<void> Function() onRequestEntry,
  required VoidCallback onDelete,
}) async {
  final division = await _loadDivisionFromAccounts();
  final area = await _loadCurrentArea();

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

  if (row == null) {
    final r2 = await db.query(
      OfflineAuthDb.tableAccounts,
      columns: const ['division'],
      where: 'isSelected = 1',
      limit: 1,
    );
    if (r2.isNotEmpty) row = r2.first;
  }

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

  if (row == null) {
    final r2 = await db.query(
      OfflineAuthDb.tableAccounts,
      columns: const ['currentArea', 'selectedArea'],
      where: 'isSelected = 1',
      limit: 1,
    );
    if (r2.isNotEmpty) row = r2.first;
  }

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

            // ⛔ 비활성화: 정산(사전 정산)
            ElevatedButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text("정산(사전 정산)"),
              onPressed: null, // 비활성화
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.grey.shade200,
                foregroundColor: Colors.grey.shade600,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ⛔ 비활성화: 정산 취소(잠금 해제) - 로직 삭제
            ElevatedButton.icon(
              icon: const Icon(Icons.lock_open),
              label: const Text("정산 취소"),
              onPressed: null, // 비활성화
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.grey.shade100,
                foregroundColor: Colors.black38,
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

            // ⛔ 비활성화: 로그 확인
            ElevatedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text("로그 확인"),
              onPressed: null, // 비활성화
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.grey.shade100,
                foregroundColor: Colors.black38,
                elevation: 0,
                side: const BorderSide(color: Colors.black12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ⛔ 비활성화: 정보 수정 (신규)
            ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text("정보 수정"),
              onPressed: null, // 비활성화
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.grey.shade100,
                foregroundColor: Colors.black38,
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
