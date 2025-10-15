// lib/screens/type_pages/offline_departure_request_page.dart
//
// 변경 요약 👇
// - SQLite만 사용
// - PlateType 의존 제거
// - 출차 요청 목록/선택/출차 완료
// - 안내 바텀시트는 로컬
// - ✅ DB 변경 알림(OfflineDbNotifier) 구독/발행
// - ✅ 출차 완료 TTS 반영 ("차량 뒷번호#### 출차 완료되었습니다.")
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../sql/offline_auth_db.dart';
import '../sql/offline_auth_service.dart';

// ▼ DB 변경 알림 (전역 Notifier)
import '../sql/offline_db_notifier.dart';

import '../../utils/snackbar_helper.dart';
import '../offline_navigation/offline_top_navigation.dart';

// 컨트롤 버튼
import 'offline_departure_request_package/offline_departure_request_control_buttons.dart';

// ✅ TTS
import '../../offlines/tts/offline_tts.dart';

const String _kStatusDepartureRequests = 'departureRequests';
const String _kStatusDepartured       = 'departured';

class OfflineDepartureRequestPage extends StatefulWidget {
  const OfflineDepartureRequestPage({super.key});

  @override
  State<OfflineDepartureRequestPage> createState() => _OfflineDepartureRequestPageState();
}

class _OfflineDepartureRequestPageState extends State<OfflineDepartureRequestPage> {
  bool _isSorted = true;
  bool _isLocked = false;

  bool _openingSearch = false;
  VoidCallback? _dbListener;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[DepartureRequest] $msg');
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _dbListener = () {
      if (mounted) setState(() {});
    };
    OfflineDbNotifier.instance.tick.addListener(_dbListener!);
  }

  @override
  void dispose() {
    if (_dbListener != null) {
      OfflineDbNotifier.instance.tick.removeListener(_dbListener!);
    }
    super.dispose();
  }

  Future<(String uid, String uname)> _loadSessionIdentity() async {
    final s = await OfflineAuthService.instance.currentSession();
    final uid = (s?.userId ?? '').trim();
    final uname = (s?.name ?? '').trim();
    return (uid, uname);
  }

  Future<String> _loadCurrentArea() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

    String area = '';

    if (uid.isNotEmpty) {
      final r1 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'userId = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (r1.isNotEmpty) {
        area = ((r1.first['currentArea'] as String?) ?? (r1.first['selectedArea'] as String?) ?? '').trim();
      }
    }

    if (area.isEmpty) {
      final r2 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'isSelected = 1',
        limit: 1,
      );
      if (r2.isNotEmpty) {
        area = ((r2.first['currentArea'] as String?) ?? (r2.first['selectedArea'] as String?) ?? '').trim();
      }
    }

    return area;
  }

  Future<void> _showSearchDialog() async {
    if (_openingSearch) return;
    _openingSearch = true;
    try {
      if (!mounted) return;
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
                            '번호판 위치 검색',
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
                      '입차 요청 및 출차 요청에 있는 번호판 위치를 검색할 수 있습니다.',
                      style: TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _openingSearch = false;
    }
  }

  // ─────────── 출차 완료 + TTS ───────────
  Future<void> _handleDepartureCompleted() async {
    if (_isLocked) {
      showSelectedSnackbar(context, '화면이 잠금 상태입니다.');
      return;
    }

    try {
      final db = await OfflineAuthDb.instance.database;
      final (uid, uname) = await _loadSessionIdentity();

      // fourDigit도 함께 조회 → "뒷번호####"
      final rows = await db.query(
        OfflineAuthDb.tablePlates,
        columns: const ['id', 'plate_number', 'plate_four_digit'],
        where: '''
          is_selected = 1
          AND COALESCE(status_type,'') = ?
          AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
        ''',
        whereArgs: [_kStatusDepartureRequests, uid, uname],
        orderBy: 'COALESCE(updated_at, created_at) DESC',
        limit: 1,
      );

      if (rows.isEmpty) {
        showFailedSnackbar(context, '선택된 출차 요청이 없습니다.');
        return;
      }

      final id   = rows.first['id'] as int;
      final pn   = (rows.first['plate_number'] as String?)?.trim() ?? '';
      final four = (rows.first['plate_four_digit'] as String?)?.trim() ?? '';

      await db.update(
        OfflineAuthDb.tablePlates,
        {
          'status_type': _kStatusDepartured,
          'is_selected': 0,
          'updated_at': _nowMs(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      // 변경 알림 + ✅ TTS (출차 완료)
      OfflineDbNotifier.instance.bump();
      await OfflineTts.instance.sayDepartureCompleted(
        plateNumber: pn.isNotEmpty ? pn : null,
        fourDigit  : four.isNotEmpty ? four : null,
      );

      if (!mounted) return;
      showSuccessSnackbar(context, '출차 완료: ${pn.isNotEmpty ? pn : (four.isNotEmpty ? "****-$four" : "미상")}');
      setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint("출차 완료 처리 실패: $e");
      if (mounted) showFailedSnackbar(context, "출차 완료 중 오류 발생: $e");
    }
  }
  // ──────────────────────────────────────

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
        whereArgs: [_kStatusDepartureRequests, uid, uname],
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

    OfflineDbNotifier.instance.bump();

    if (mounted) setState(() {});
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
      whereArgs: [_kStatusDepartureRequests, uid, uname],
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

    OfflineDbNotifier.instance.bump();

    return true;
  }

  void _toggleSortIcon() => setState(() => _isSorted = !_isSorted);
  void _toggleLock()     => setState(() => _isLocked = !_isLocked);

  String _buildBillingSummary({
    required int basicAmount,
    required int basicStd,
    required int addAmount,
    required int addStd,
  }) {
    final parts = <String>[];
    if (basicAmount > 0) {
      parts.add('기본 ${basicAmount}원${basicStd > 0 ? ' / ${basicStd}분' : ''}');
    }
    if (addAmount > 0) {
      parts.add('추가 ${addAmount}원${addStd > 0 ? ' / ${addStd}분' : ''}');
    }
    return parts.isEmpty ? '' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (await _clearSelectedIfAny()) {
          _log('clear selection');
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
        body: FutureBuilder<Widget>(
          future: _buildListBody(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 3));
            }
            if (snap.hasError) {
              return Center(child: Text('목록 로드 실패: ${snap.error}'));
            }
            return snap.data ?? const SizedBox.shrink();
          },
        ),
        bottomNavigationBar: OfflineDepartureRequestControlButtons(
          isSorted: _isSorted,
          isLocked: _isLocked,
          showSearchDialog: _showSearchDialog,
          toggleSortIcon: _toggleSortIcon,
          toggleLock: _toggleLock,
          handleDepartureCompleted: _handleDepartureCompleted,
        ),
      ),
    );
  }

  Future<Widget> _buildListBody() async {
    final db = await OfflineAuthDb.instance.database;
    final area = await _loadCurrentArea();
    if (area.isEmpty) {
      return const Center(
        child: Text('현재 지역 정보를 확인할 수 없습니다.'),
      );
    }

    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const [
        'id',
        'plate_number',
        'plate_four_digit',
        'location',
        'billing_type',
        'basic_amount',
        'basic_standard',
        'add_amount',
        'add_standard',
        'request_time',
        'is_selected',
      ],
      where: "COALESCE(status_type,'') = ? AND area = ?",
      whereArgs: [_kStatusDepartureRequests, area],
      orderBy: _isSorted
          ? 'COALESCE(request_time, COALESCE(updated_at, created_at)) DESC'
          : 'COALESCE(request_time, COALESCE(updated_at, created_at)) ASC',
      limit: 300,
    );

    if (rows.isEmpty) {
      return const Center(
        child: Text(
          '오프라인 출차 요청이 없습니다.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final tiles = rows.map((r) {
      final id = r['id'] as int;
      final pn = (r['plate_number'] as String?)?.trim();
      final four = (r['plate_four_digit'] as String?)?.trim() ?? '';
      final loc = (r['location'] as String?)?.trim() ?? '';
      final billing = (r['billing_type'] as String?)?.trim() ?? '';
      final basicAmount = (r['basic_amount'] as int?) ?? 0;
      final basicStd = (r['basic_standard'] as int?) ?? 0;
      final addAmount = (r['add_amount'] as int?) ?? 0;
      final addStd = (r['add_standard'] as int?) ?? 0;
      final selected = ((r['is_selected'] as int?) ?? 0) != 0;

      final title = (pn != null && pn.isNotEmpty)
          ? pn
          : (four.isNotEmpty ? '****-$four' : '미상');
      final locationText = loc.isNotEmpty ? loc : '위치 미지정';

      final billingSummary = _buildBillingSummary(
        basicAmount: basicAmount,
        basicStd: basicStd,
        addAmount: addAmount,
        addStd: addStd,
      );
      final billingText = billing.isEmpty
          ? '정산 미지정'
          : (billingSummary.isEmpty ? '정산 $billing' : '정산 $billing ($billingSummary)');

      return InkWell(
        onTap: () async {
          if (_isLocked) {
            showSelectedSnackbar(context, '화면이 잠금 상태입니다.');
            return;
          }
          await _togglePlateSelection(id);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.black.withOpacity(0.04) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.black : Colors.grey.shade300,
              width: selected ? 1.6 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.directions_car,
                size: 22,
                color: selected ? Colors.black : Colors.grey[700],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      locationText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      billingText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      );
    }).toList();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: tiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => tiles[i],
    );
  }
}
