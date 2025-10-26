import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback

// ▼ SQLite / 세션
import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/dialog/plate_remove_dialog.dart';

class _Palette {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const danger = Color(0xFFD32F2F);
  static const success = Color(0xFF2E7D32);
}

const String _kStatusDepartureRequests = 'departureRequests';
const String _kStatusParkingRequests = 'parkingRequests';
const String _kStatusParkingCompleted = 'parkingCompleted';
const String _kStatusDepartured = 'departured';

class OfflineDepartureRequestControlButtons extends StatelessWidget {
  final bool isSorted;
  final bool isLocked;

  final VoidCallback showSearchDialog;
  final VoidCallback toggleSortIcon;
  final VoidCallback handleDepartureCompleted;
  final VoidCallback toggleLock;

  const OfflineDepartureRequestControlButtons({
    super.key,
    required this.isSorted,
    required this.isLocked,
    required this.showSearchDialog,
    required this.toggleSortIcon,
    required this.handleDepartureCompleted,
    required this.toggleLock,
  });

  Future<(String uid, String uname)> _identity() async {
    final s = await OfflineAuthService.instance.currentSession();
    return ((s?.userId ?? '').trim(), (s?.name ?? '').trim());
  }

  String _asStr(Object? v) => (v?.toString() ?? '').trim();

  int _asInt(Object? v) => switch (v) {
        int i => i,
        num n => n.toInt(),
        String s => int.tryParse(s) ?? 0,
        _ => 0,
      };

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  Future<Map<String, Object?>?> _getSelectedPlateRow() async {
    final db = await OfflineAuthDb.instance.database;
    final (uid, uname) = await _identity();
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
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<bool> _hasSelectedPlate() async {
    final r = await _getSelectedPlateRow();
    return r != null && ((_asInt(r['is_selected'])) != 0);
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
        } catch (_) {
          /* ignore */
        }
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

  Future<void> _showBillingInfoFullSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 1,
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
                    '기본 정산, 할증, 할인을 적용할 수 있습니다.\n'
                    '현재 버전에서는 정산 정보를 확인만 할 수 있습니다.',
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateStatus({
    required BuildContext context,
    required int id,
    required String toStatus,
    String? locationOverride,
    String? plateNumberForToast,
  }) async {
    try {
      final db = await OfflineAuthDb.instance.database;
      final (uid, uname) = await _identity();

      final values = <String, Object?>{
        'status_type': toStatus,
        'is_selected': 0,
        'updated_at': _nowMs(),
      };
      if (locationOverride != null) {
        values['location'] = locationOverride;
      }

      await db.update(
        OfflineAuthDb.tablePlates,
        values,
        where: 'id = ?',
        whereArgs: [id],
      );

      await _appendLog(id, {
        'action': '상태 변경',
        'to': toStatus,
        'performedBy': uname.isNotEmpty ? uname : uid,
        'timestamp': DateTime.now().toIso8601String(),
      });

      HapticFeedback.mediumImpact();
      showSuccessSnackbar(
        context,
        '처리 완료'
        '${plateNumberForToast != null && plateNumberForToast.trim().isNotEmpty ? ': $plateNumberForToast' : ''}',
      );
    } catch (e) {
      showFailedSnackbar(context, '상태 변경 실패: $e');
    }
  }

  Future<void> _showQuickActionsSheet(BuildContext context) async {
    final selectedRow = await _getSelectedPlateRow();
    if (selectedRow == null) return;

    final id = _asInt(selectedRow['id']);
    final plateNumber = _asStr(selectedRow['plate_number']);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.receipt_long),
              title: Text('로그 확인'),
              enabled: false,
            ),
            const ListTile(
              leading: Icon(Icons.edit),
              title: Text('정보 수정'),
              enabled: false,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('입차 요청으로 변경'),
              onTap: () async {
                Navigator.pop(context);
                await _updateStatus(
                  context: context,
                  id: id,
                  toStatus: _kStatusParkingRequests,
                  locationOverride: '미지정',
                  plateNumberForToast: plateNumber,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_parking),
              title: const Text('입차 완료 처리'),
              onTap: () async {
                Navigator.pop(context);
                await _updateStatus(
                  context: context,
                  id: id,
                  toStatus: _kStatusParkingCompleted,
                  plateNumberForToast: plateNumber,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('출차 완료 처리'),
              onTap: () async {
                Navigator.pop(context);
                await _updateStatus(
                  context: context,
                  id: id,
                  toStatus: _kStatusDepartured,
                  plateNumberForToast: plateNumber,
                );
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
                      await db.delete(
                        OfflineAuthDb.tablePlates,
                        where: 'id = ?',
                        whereArgs: [id],
                      );
                      showSuccessSnackbar(context, "삭제 완료: $plateNumber");
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

    return FutureBuilder<bool>(
      future: _hasSelectedPlate(),
      builder: (context, snap) {
        final bool isPlateSelected = snap.data == true;

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
                  isPlateSelected ? Icons.payments : (isLocked ? Icons.lock : Icons.lock_open),
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

            if (!isPlateSelected) {
              if (index == 0) {
                toggleLock();
              } else if (index == 1) {
                showSearchDialog();
              } else if (index == 2) {
                toggleSortIcon();
              }
              return;
            }

            if (index == 0) {
              await _showBillingInfoFullSheet(context);
            } else if (index == 1) {
              handleDepartureCompleted(); // 페이지에서 SQLite 전환 처리
            } else if (index == 2) {
              await _showQuickActionsSheet(context);
            }
          },
        );
      },
    );
  }
}
