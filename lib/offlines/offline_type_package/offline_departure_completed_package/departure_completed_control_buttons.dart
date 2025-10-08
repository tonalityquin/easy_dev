import 'dart:convert';

import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

/// SQLite 전용: 하단 컨트롤
/// - 선택된 departureCompleted 1건이 있으면 “상태 수정”(간단 액션 시트)
/// - 아니면 “번호판 검색” 버튼(상위에서 처리)
class DepartureCompletedControlButtons extends StatefulWidget {
  final bool isSearchMode;
  final VoidCallback onResetSearch;
  final VoidCallback onShowSearchDialog;

  const DepartureCompletedControlButtons({
    super.key,
    required this.isSearchMode,
    required this.onResetSearch,
    required this.onShowSearchDialog,
  });

  @override
  State<DepartureCompletedControlButtons> createState() => _DepartureCompletedControlButtonsState();
}

class _DepartureCompletedControlButtonsState extends State<DepartureCompletedControlButtons> {
  Map<String, Object?>? _selectedRow;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshSelected();
  }

  Future<void> _refreshSelected() async {
    try {
      setState(() => _loading = true);
      final db = await OfflineAuthDb.instance.database;
      final s = await OfflineAuthService.instance.currentSession();
      final uid = (s?.userId ?? '').trim();
      final uname = (s?.name ?? '').trim();

      final rows = await db.query(
        OfflineAuthDb.tablePlates,
        where: '''
          is_selected = 1
          AND COALESCE(status_type,'') = ?
          AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
        ''',
        whereArgs: ['departureCompleted', uid, uname],
        orderBy: 'COALESCE(updated_at, created_at) DESC',
        limit: 1,
      );
      _selectedRow = rows.isNotEmpty ? rows.first : null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setLockedFee({required bool locked}) async {
    if (_selectedRow == null) return;
    final db = await OfflineAuthDb.instance.database;

    final id = _selectedRow!['id'] as int;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final values = <String, Object?>{
      'is_locked_fee': locked ? 1 : 0,
      'updated_at': nowMs,
    };
    if (!locked) {
      values['locked_at_time_in_seconds'] = null;
      values['locked_fee_amount'] = null;
      values['payment_method'] = null;
    }

    await db.update(
      OfflineAuthDb.tablePlates,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _appendLog(
      id,
      {
        'action': locked ? '정산 잠금' : '정산 해제',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    await _refreshSelected();
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
    List<dynamic> logs = [];
    if (r.isNotEmpty) {
      final raw = r.first['logs'];
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          logs = jsonDecode(raw) as List<dynamic>;
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

  Future<void> _showStatusSheet() async {
    if (_selectedRow == null) return;
    final isLocked = ((_selectedRow!['is_locked_fee'] as int?) ?? 0) != 0;

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isLocked ? Icons.lock_open : Icons.lock),
              title: Text(isLocked ? '정산 해제' : '정산 잠금'),
              onTap: () async {
                Navigator.pop(context);
                await _setLockedFee(locked: !isLocked);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final id = _selectedRow!['id'] as int;
                final db = await OfflineAuthDb.instance.database;
                await db.delete(
                  OfflineAuthDb.tablePlates,
                  where: 'id = ?',
                  whereArgs: [id],
                );
                await _refreshSelected();
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
    final isPlateSelected = !_loading && _selectedRow != null;

    return BottomAppBar(
      color: Colors.white,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Center(
            child: isPlateSelected
                ? TextButton.icon(
              onPressed: _showStatusSheet,
              icon: const Icon(Icons.settings, color: Colors.black87),
              label: const Text(
                '상태 수정',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            )
                : TextButton.icon(
              onPressed: widget.isSearchMode ? widget.onResetSearch : widget.onShowSearchDialog,
              icon: Icon(
                widget.isSearchMode ? Icons.cancel : Icons.search,
                color: widget.isSearchMode ? Colors.orange[600] : Colors.grey[800],
              ),
              label: Text(
                widget.isSearchMode ? '검색 초기화' : '번호판 검색',
                style: TextStyle(
                  color: widget.isSearchMode ? Colors.orange[600] : Colors.grey[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
