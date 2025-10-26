import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../sql/offline_auth_db.dart';
import '../sql/offline_auth_service.dart';

import '../../utils/snackbar_helper.dart';

import 'offline_parking_completed_package/widgets/offline_signature_plate_search_bottom_sheet/offline_parking_completed_search_bottom_sheet.dart';
import '../offline_navigation/offline_top_navigation.dart';

import 'offline_parking_completed_package/offline_parking_completed_control_buttons.dart';
import 'offline_parking_completed_package/offline_parking_completed_location_picker.dart';
import 'offline_parking_completed_package/widgets/offline_parking_status_page.dart';

const String _kStatusParkingCompleted = 'parkingCompleted';
const String _kStatusParkingRequests = 'parkingRequests';

enum ParkingViewMode { status, locationPicker, plateList }

class OfflineParkingCompletedPage extends StatefulWidget {
  const OfflineParkingCompletedPage({super.key});

  static void reset(GlobalKey key) {
    (key.currentState as _OfflineParkingCompletedPageState?)?._resetInternalState();
  }

  @override
  State<OfflineParkingCompletedPage> createState() => _OfflineParkingCompletedPageState();
}

class _OfflineParkingCompletedPageState extends State<OfflineParkingCompletedPage> {
  ParkingViewMode _mode = ParkingViewMode.status;
  String? _selectedParkingArea;
  bool _isSorted = true;
  bool _isLocked = true;

  int _statusKeySeed = 0;

  bool _openingSheet = false;

  final Map<String, int> _locationLimitCache = {};

  void _log(String msg) {
    if (kDebugMode) debugPrint('[ParkingCompleted] $msg');
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  Future<String> _loadCurrentArea() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

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
    ))
        .firstOrNull;

    final area = ((row?['currentArea'] as String?) ?? (row?['selectedArea'] as String?) ?? '').trim();
    return area;
  }

  Future<(String uid, String uname)> _loadSessionIdentity() async {
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();
    final uname = (session?.name ?? '').trim();
    return (uid, uname);
  }

  void _resetInternalState() {
    setState(() {
      _mode = ParkingViewMode.status;
      _selectedParkingArea = null;
      _isSorted = true;
      _isLocked = true;
      _statusKeySeed++;
    });
    _log('reset page state');
  }

  void _toggleSortIcon() {
    setState(() => _isSorted = !_isSorted);
    _log(_isSorted ? 'sort → 최신순' : 'sort → 오래된순');
  }

  Future<void> _showSearchDialog(BuildContext context) async {
    final currentArea = await _loadCurrentArea();
    _log('open search dialog');
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return OfflineParkingCompletedSearchBottomSheet(
          onSearch: (_) {},
          area: currentArea,
        );
      },
    );
  }

  void _resetParkingAreaFilter() {
    setState(() {
      _selectedParkingArea = null;
      _mode = ParkingViewMode.status;
    });
    _log('reset location filter');
  }

  Future<int?> _getLocationLimit(String area, String loc) async {
    final key = '$area::$loc';
    if (_locationLimitCache.containsKey(key)) return _locationLimitCache[key];

    final db = await OfflineAuthDb.instance.database;

    List<Map<String, Object?>> rows = await db.query(
      OfflineAuthDb.tableLocations,
      columns: const ['capacity'],
      where: 'area = ? AND location_name = ?',
      whereArgs: [area, loc],
      limit: 1,
    );

    if (rows.isEmpty) {
      rows = await db.query(
        OfflineAuthDb.tableLocations,
        columns: const ['capacity'],
        where: 'area = ? AND location_name = ?',
        whereArgs: [area, loc],
        limit: 1,
      );
    }

    if (rows.isEmpty) return null;
    final cap = (rows.first['capacity'] as int?) ?? 0;
    if (cap <= 0) return null;

    _locationLimitCache[key] = cap;
    return cap;
  }

  Future<int> _countAt(String area, String loc) async {
    final db = await OfflineAuthDb.instance.database;
    final res = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
        FROM ${OfflineAuthDb.tablePlates}
       WHERE COALESCE(status_type,'') = ?
         AND area = ?
         AND location = ?
      ''',
      [_kStatusParkingCompleted, area, loc],
    );
    final c = (res.isNotEmpty ? res.first['c'] : 0) as int? ?? 0;
    return c;
  }

  Future<List<String>> _fetchPlateNumbers(String area, String loc, int limit) async {
    final db = await OfflineAuthDb.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT plate_number, plate_four_digit
        FROM ${OfflineAuthDb.tablePlates}
       WHERE COALESCE(status_type,'') = ?
         AND area = ?
         AND location = ?
       ORDER BY COALESCE(updated_at, created_at) DESC
       LIMIT ?
      ''',
      [_kStatusParkingCompleted, area, loc, limit],
    );

    final out = <String>[];
    for (final r in rows) {
      final pn = (r['plate_number'] as String?)?.trim();
      if (pn != null && pn.isNotEmpty) {
        out.add(pn);
      } else {
        final four = (r['plate_four_digit'] as String?)?.trim() ?? '';
        if (four.isNotEmpty) out.add('****-$four');
      }
    }
    return out;
  }

  Future<void> _handleDepartureRequested(BuildContext context) async {
    try {
      final db = await OfflineAuthDb.instance.database;
      final (uid, uname) = await _loadSessionIdentity();

      final rows = await db.query(
        OfflineAuthDb.tablePlates,
        columns: const ['id', 'plate_number'],
        where: '''
          is_selected = 1
          AND COALESCE(status_type,'') = ?
          AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
        ''',
        whereArgs: [_kStatusParkingCompleted, uid, uname],
        orderBy: 'COALESCE(updated_at, created_at) DESC',
        limit: 1,
      );

      if (rows.isEmpty) {
        showFailedSnackbar(context, '선택된 차량이 없습니다.');
        return;
      }

      final id = rows.first['id'] as int;
      await db.update(
        OfflineAuthDb.tablePlates,
        {
          'status_type': _kStatusParkingRequests,
          'is_selected': 0,
          'updated_at': _nowMs(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      showSuccessSnackbar(context, '출차 요청이 완료되었습니다.');
    } catch (e) {
      showFailedSnackbar(context, '출차 요청 중 오류: $e');
    }
  }

  void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) async {
    _log('stub: entry parking request $plateNumber ($area)');
    showSuccessSnackbar(context, "입차 요청 처리: $plateNumber ($area)");
  }

  Future<void> _tryShowPlateNumbersBottomSheet(String locationName) async {
    if (_isLocked) {
      showFailedSnackbar(context, '잠금 상태입니다. 잠금을 해제한 뒤 이용해 주세요.');
      return;
    }
    if (_openingSheet) return;
    _openingSheet = true;

    String raw = locationName.trim();
    String? child;
    final hyphenIdx = raw.lastIndexOf(' - ');
    if (hyphenIdx != -1) {
      child = raw.substring(hyphenIdx + 3).trim();
    }

    try {
      final area = await _loadCurrentArea();
      if (area.isEmpty) {
        showFailedSnackbar(context, '현재 지역 정보를 확인할 수 없습니다.');
        return;
      }

      String selectedLoc = raw;
      int locCnt = await _countAt(area, raw);
      if (locCnt == 0 && child != null && child.isNotEmpty) {
        selectedLoc = child;
        locCnt = await _countAt(area, child);
      }

      if (locCnt == 0) {
        showSelectedSnackbar(context, '해당 구역에 입차 완료 차량이 없습니다.');
        return;
      }

      final limit = await _getLocationLimit(area, selectedLoc);
      if (limit == null || limit <= 0) {
        showFailedSnackbar(context, '"$selectedLoc" 리미트가 설정되지 않았습니다. 관리자에 문의하세요.');
        return;
      }

      if (locCnt > limit) {
        showFailedSnackbar(context, '목록 잠금: "$selectedLoc"에 입차 완료 $locCnt대(>$limit) 입니다.');
        return;
      }

      final plateNumbers = await _fetchPlateNumbers(area, selectedLoc, limit);

      if (plateNumbers.isEmpty) {
        showSelectedSnackbar(context, '해당 구역에 입차 완료 차량이 없습니다.');
        return;
      }

      if (!mounted) return;
      await _showPlateNumberListSheet(locationName: locationName, plates: plateNumbers);
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '번호판 목록 표시 실패: $e');
    } finally {
      _openingSheet = false;
    }
  }

  Future<void> _showPlateNumberListSheet({
    required String locationName,
    required List<String> plates,
  }) async {
    final double initialFactor = plates.length <= 3 ? 0.45 : (plates.length <= 7 ? 0.60 : 0.80);

    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surface;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: initialFactor,
          minChildSize: initialFactor,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceColor, // 다크모드 대응
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.dividerColor.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.local_parking),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '"$locationName" 번호판',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${plates.length}대',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: plates.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final pn = plates[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.directions_car),
                            title: Text(
                              pn,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _clearSelectedIfAny() async {
    final db = await OfflineAuthDb.instance.database;
    final (uid, uname) = await _loadSessionIdentity();

    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const ['id'],
      where: '''
        is_selected = 1
        AND COALESCE(status_type,'') = ?
        AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
      ''',
      whereArgs: [_kStatusParkingCompleted, uid, uname],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final id = rows.first['id'] as int;
    await db.update(
      OfflineAuthDb.tablePlates,
      {'is_selected': 0, 'updated_at': _nowMs()},
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (await _clearSelectedIfAny()) {
          _log('clear selection');
          return false;
        }

        if (_mode == ParkingViewMode.plateList) {
          setState(() => _mode = ParkingViewMode.locationPicker);
          _log('back → locationPicker');
          return false;
        } else if (_mode == ParkingViewMode.locationPicker) {
          setState(() => _mode = ParkingViewMode.status);
          _log('back → status');
          return false;
        }

        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const OfflineTopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: _buildBody(context),
        bottomNavigationBar: OfflineParkingCompletedControlButtons(
          isParkingAreaMode: _mode == ParkingViewMode.plateList,
          isStatusMode: _mode == ParkingViewMode.status,
          isLocationPickerMode: _mode == ParkingViewMode.locationPicker,
          isSorted: _isSorted,
          isLocked: _isLocked,
          onToggleLock: () {
            setState(() => _isLocked = !_isLocked);
            _log(_isLocked ? 'lock ON' : 'lock OFF');
          },
          showSearchDialog: () => _showSearchDialog(context),
          resetParkingAreaFilter: _resetParkingAreaFilter,
          toggleSortIcon: _toggleSortIcon,
          handleEntryParkingRequest: handleEntryParkingRequest,
          handleDepartureRequested: _handleDepartureRequested,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_mode) {
      case ParkingViewMode.status:
        return GestureDetector(
          onTap: () {
            setState(() => _mode = ParkingViewMode.locationPicker);
            _log('open location picker');
          },
          child: OfflineParkingStatusPage(
            key: ValueKey('status-$_statusKeySeed'),
            isLocked: _isLocked,
          ),
        );

      case ParkingViewMode.locationPicker:
        return OfflineParkingCompletedLocationPicker(
          onLocationSelected: (locationName) {
            _selectedParkingArea = locationName;
            _tryShowPlateNumbersBottomSheet(locationName);
          },
          isLocked: _isLocked,
        );

      case ParkingViewMode.plateList:
        return FutureBuilder<Widget>(
          future: _buildPlateListBody(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 3));
            }
            if (snap.hasError) {
              return Center(child: Text('목록 로드 실패: ${snap.error}'));
            }
            return snap.data ?? const SizedBox.shrink();
          },
        );
    }
  }

  Future<Widget> _buildPlateListBody() async {
    final db = await OfflineAuthDb.instance.database;
    final area = await _loadCurrentArea();
    if (area.isEmpty) {
      return const Center(child: Text('현재 지역 정보를 확인할 수 없습니다.'));
    }

    final whereParts = <String>[
      "COALESCE(status_type,'') = ?",
      'area = ?',
    ];
    final args = <Object?>[_kStatusParkingCompleted, area];

    if (_selectedParkingArea != null && _selectedParkingArea!.trim().isNotEmpty) {
      whereParts.add('location = ?');
      args.add(_selectedParkingArea!.trim());
    }

    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const ['id', 'plate_number', 'plate_four_digit', 'location', 'is_selected'],
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: _isSorted ? 'COALESCE(updated_at, created_at) DESC' : 'COALESCE(updated_at, created_at) ASC',
      limit: 200,
    );

    final listTiles = rows.map((r) {
      final int id = r['id'] as int;
      final pn = (r['plate_number'] as String?)?.trim();
      final four = (r['plate_four_digit'] as String?)?.trim() ?? '';
      final loc = (r['location'] as String?)?.trim() ?? '';
      final selected = ((r['is_selected'] as int?) ?? 0) != 0;

      final title = (pn != null && pn.isNotEmpty) ? pn : (four.isNotEmpty ? '****-$four' : '미상');

      return ListTile(
        dense: true,
        leading: Icon(selected ? Icons.check_circle : Icons.circle_outlined),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(loc),
        onTap: () async {
          await _togglePlateSelection(id);
          if (!mounted) return;
          setState(() {});
        },
      );
    }).toList();

    return ListView.separated(
      padding: const EdgeInsets.all(8.0),
      itemCount: listTiles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => listTiles[i],
    );
  }

  Future<void> _togglePlateSelection(int id) async {
    final db = await OfflineAuthDb.instance.database;
    final (uid, uname) = await _loadSessionIdentity();

    await db.transaction((txn) async {
      final r = await txn.query(
        OfflineAuthDb.tablePlates,
        columns: const ['is_selected'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final curSel = r.isNotEmpty ? ((r.first['is_selected'] as int?) ?? 0) : 0;

      await txn.update(
        OfflineAuthDb.tablePlates,
        {'is_selected': 0},
        where: "COALESCE(status_type,'') = ? AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)",
        whereArgs: [_kStatusParkingCompleted, uid, uname],
      );

      await txn.update(
        OfflineAuthDb.tablePlates,
        {
          'is_selected': curSel == 0 ? 1 : 0,
          'selected_by': uid,
          'user_name': uname,
          'updated_at': _nowMs(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }
}
