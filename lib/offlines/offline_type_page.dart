// lib/offlines/offline_type_page.dart
// (원본에서 기능 유지 + ✅ TTS 추가)

/// ignore_for_file: use_build_context_synchronously
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../enums/plate_type.dart';

import 'offline_input_package/offline_input_plate_screen.dart';
import 'offline_states/page/offline_page_state.dart';
import 'offline_states/page/offline_page_info.dart';

import 'offline_type_package/common_widgets/dashboard_bottom_sheet/offline_home_dash_board_bottom_sheet.dart';
import '../utils/snackbar_helper.dart';

// ▼ SQLite / 세션
import 'sql/offline_auth_db.dart';
import 'sql/offline_auth_service.dart';

// ▼ 출차요청 바텀시트(번호판만 크게)
import 'tablet/offline_departure_bottom_sheet.dart';

// ✅ TTS
import 'tts/offline_tts.dart';

class _Palette {
  static const base = Color(0xFFF4511E);
  static const dark = Color(0xFFD84315);
  static const fg = Color(0xFFFFFFFF);
}

class OfflineTypePage extends StatefulWidget {
  const OfflineTypePage({super.key});

  @override
  State<OfflineTypePage> createState() => _OfflineTypePageState();
}

class _OfflineTypePageState extends State<OfflineTypePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await OfflineAuthDb.instance.database;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OfflinePageState(pages: defaultPages),
      child: Builder(
        builder: (context) {
          final pageState = context.read<OfflinePageState>();

          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) async {
              if (didPop) return;
              final currentPage = pageState.pages[pageState.selectedIndex];
              final type = currentPage.collectionKey;
              await _unselectOneIfAnyFor(type);
            },
            child: Scaffold(
              body: const RefreshableBody(),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _ChatDashboardBar(),
                    const PageBottomNavigation(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        height: 48,
                        child: Image.asset('assets/images/pelican.png'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _unselectOneIfAnyFor(PlateType type) async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();

    final uid = (session?.userId ?? '').trim();
    final uname = (session?.name ?? '').trim();
    final statusKey = _statusTypeKey(type);

    await db.transaction((txn) async {
      final where = <String>['is_selected = 1'];
      final args = <Object?>[];

      if (statusKey.isNotEmpty) {
        where.add('COALESCE(status_type, \'\') = ?');
        args.add(statusKey);
      }
      if (uid.isNotEmpty || uname.isNotEmpty) {
        where.add('(COALESCE(selected_by, \'\') = ? OR COALESCE(user_name, \'\') = ?)');
        args.add(uid);
        args.add(uname);
      }

      final rows = await txn.query(
        OfflineAuthDb.tablePlates,
        columns: const ['id'],
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'COALESCE(updated_at, created_at) DESC',
        limit: 1,
      );

      int? targetId;
      if (rows.isNotEmpty) {
        targetId = rows.first['id'] as int?;
      } else {
        final rows2 = await txn.query(
          OfflineAuthDb.tablePlates,
          columns: const ['id'],
          where: statusKey.isNotEmpty ? 'is_selected = 1 AND COALESCE(status_type, \'\') = ?' : 'is_selected = 1',
          whereArgs: statusKey.isNotEmpty ? [statusKey] : null,
          orderBy: 'COALESCE(updated_at, created_at) DESC',
          limit: 1,
        );
        if (rows2.isNotEmpty) {
          targetId = rows2.first['id'] as int?;
        }
      }

      if (targetId != null) {
        await txn.update(
          OfflineAuthDb.tablePlates,
          {'is_selected': 0},
          where: 'id = ?',
          whereArgs: [targetId],
        );
      }
    });
  }

  String _statusTypeKey(PlateType type) => type.name;
}

class _ChatDashboardBar extends StatelessWidget {
  const _ChatDashboardBar();

  static const String _kStatusParkingCompleted   = 'parkingCompleted';
  static const String _kStatusDepartureRequests  = 'departureRequests';

  static Future<void> _onRandomDepartureRequest(BuildContext context) async {
    // HQ 단일 지역 or 세션 지역 — 기존 로직 유지
    final area = await _loadCurrentArea();
    if (area.isEmpty) {
      showFailedSnackbar(context, '현재 지역 정보를 확인할 수 없습니다.');
      return;
    }

    try {
      final db = await OfflineAuthDb.instance.database;

      final rows = await db.query(
        OfflineAuthDb.tablePlates,
        columns: const ['id', 'plate_number', 'plate_four_digit'],
        where: '''
          COALESCE(status_type,'') = ?
          AND LOWER(TRIM(area)) = LOWER(TRIM(?))
        ''',
        whereArgs: [_kStatusParkingCompleted, area],
        limit: 500,
      );

      if (rows.isEmpty) {
        showSelectedSnackbar(context, '입차 완료 상태 차량이 없습니다.');
        return;
      }

      final rnd = Random();
      final picked = rows[rnd.nextInt(rows.length)];
      final id = picked['id'] as int;
      final pn = (picked['plate_number'] as String?)?.trim();
      final four = (picked['plate_four_digit'] as String?)?.trim() ?? '';
      final title = (pn != null && pn.isNotEmpty) ? pn : (four.isNotEmpty ? '****-$four' : '미상');

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      await db.update(
        OfflineAuthDb.tablePlates,
        {
          'status_type': _kStatusDepartureRequests,
          'updated_at': nowMs,
          'request_time': '$nowMs',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      // ✅ TTS: 입차완료 → 출차요청
      await OfflineTts.instance.sayDepartureRequested(
        plateNumber: pn?.isNotEmpty == true ? pn : null,
        fourDigit: (four.isNotEmpty ? four : null),
      );

      showSuccessSnackbar(context, '무작위 출차 요청 전환: $title');
    } catch (e) {
      showFailedSnackbar(context, '출차 요청 전환 중 오류: $e');
    }
  }

  static Future<String> _loadCurrentArea() async {
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

    if (row == null) {
      final r2 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'isSelected = 1',
        limit: 1,
      );
      if (r2.isNotEmpty) row = r2.first;
    }

    final area = ((row?['currentArea'] as String?) ?? (row?['selectedArea'] as String?) ?? '').trim();
    return area;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _loadCurrentArea(),
      builder: (context, snap) {
        final area = (snap.data ?? '').trim();
        final enabled = area.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: enabled ? () => _onRandomDepartureRequest(context) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: enabled ? _Palette.base : _Palette.dark.withOpacity(.35),
                    disabledBackgroundColor: Colors.white,
                    disabledForegroundColor: _Palette.dark.withOpacity(.35),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shuffle, size: 20),
                      SizedBox(width: 6),
                      Text('무작위로 출차 요청', overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const OfflineHomeDashBoardBottomSheet(),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _Palette.base,
                    foregroundColor: _Palette.fg,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 2,
                    shadowColor: _Palette.dark.withOpacity(.25),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dashboard, size: 20),
                      SizedBox(width: 6),
                      Text('대시보드'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// 이하 RefreshableBody / PageBottomNavigation 등은 원본 그대로
// (… 생략 없이 원본 동일 코드 …)
class RefreshableBody extends StatefulWidget {
  const RefreshableBody({super.key});
  @override
  State<RefreshableBody> createState() => _RefreshableBodyState();
}

class _RefreshableBodyState extends State<RefreshableBody> {
  double _dragDistance = 0.0;
  double _vDragDistance = 0.0;
  bool _sheetOpening = false;

  static const double _hDistanceThreshold = 80.0;
  static const double _hVelocityThreshold = 1000.0;

  static const double _vDistanceThreshold = 80.0;
  static const double _vVelocityThreshold = 1000.0;

  void _handleHorizontalDragEnd(BuildContext context, double velocity) {
    if (_dragDistance > _hDistanceThreshold && velocity > _hVelocityThreshold) {
      Navigator.of(context).push(_slidePage(const OfflineInputPlateScreen(), fromLeft: true));
    } else if (_dragDistance < -_hDistanceThreshold && velocity < -_hVelocityThreshold) {
      debugPrint('⏸[H] 좌->우 이외 스와이프는 현재 동작 없음');
    } else {
      debugPrint('⏸[H] 거리(${_dragDistance.toStringAsFixed(1)})/속도($velocity) 부족 → 무시');
    }
    _dragDistance = 0.0;
  }

  Future<void> _handleVerticalDragEnd(BuildContext context, DragEndDetails details) async {
    final vy = details.primaryVelocity ?? 0.0;
    final fired = _vDragDistance < -_vDistanceThreshold && vy < -_vVelocityThreshold;

    if (fired && !_sheetOpening) {
      _sheetOpening = true;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (mounted) {
        showOfflineDepartureBottomSheet(context);
      }
      _sheetOpening = false;
    } else {
      debugPrint('⏸[V] 거리(${_vDragDistance.toStringAsFixed(1)}), 속도($vy) → 조건 미충족(무시)');
    }

    _vDragDistance = 0.0;
  }

  PageRouteBuilder _slidePage(Widget page, {required bool fromLeft}) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final begin = Offset(fromLeft ? -1.0 : 1.0, 0);
        final end = Offset.zero;
        final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeInOut));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(
        context,
        details.primaryVelocity ?? 0,
      ),
      onVerticalDragUpdate: (details) => _vDragDistance += details.delta.dy,
      onVerticalDragEnd: (details) => _handleVerticalDragEnd(context, details),
      child: Consumer<OfflinePageState>(
        builder: (context, state, child) {
          return Stack(
            children: [
              _buildCurrentPage(context, state.selectedIndex),
              if (state.isLoading)
                Container(
                  color: Colors.white.withOpacity(.35),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(_Palette.base),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCurrentPage(BuildContext context, int index) {
    if (index == 0) {
      return defaultPages[0].builder(context);
    } else {
      return IndexedStack(
        index: index - 1,
        children: defaultPages.sublist(1).map((pageInfo) => pageInfo.builder(context)).toList(),
      );
    }
  }
}

class PageBottomNavigation extends StatefulWidget {
  const PageBottomNavigation({super.key});
  @override
  State<PageBottomNavigation> createState() => _PageBottomNavigationState();
}

class _PageBottomNavigationState extends State<PageBottomNavigation> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = _Palette.base;
    final unselectedColor = _Palette.dark.withOpacity(.55);

    return Consumer<OfflinePageState>(
      builder: (context, pageState, child) {
        return BottomNavigationBar(
          elevation: 0,
          currentIndex: pageState.selectedIndex,
          onTap: (index) {
            pageState.onItemTapped(
              context,
              index,
              onError: (msg) => showFailedSnackbar(context, msg),
            );
          },
          selectedItemColor: selectedColor,
          unselectedItemColor: unselectedColor,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          items: List.generate(
            pageState.pages.length,
                (index) {
              final pageInfo = pageState.pages[index];
              final isSelected = pageState.selectedIndex == index;

              final labelStyle = TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? selectedColor : unselectedColor,
              );

              if (pageInfo.title == '홈') {
                return BottomNavigationBarItem(
                  icon: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.home,
                        size: isSelected ? 32 : 28,
                        color: isSelected ? selectedColor : unselectedColor,
                      ),
                      const SizedBox(height: 2),
                      Text('홈', style: labelStyle),
                    ],
                  ),
                  label: '',
                );
              }

              final PlateType type = pageInfo.collectionKey;

              return BottomNavigationBarItem(
                icon: FutureBuilder<int>(
                  future: _countForType(type),
                  builder: (context, snap) {
                    final count = snap.data ?? 0;

                    final bool isIn = pageInfo.title == '입차 요청';
                    final bool isOut = pageInfo.title == '출차 요청';
                    Color countColor;
                    if (isIn || isOut) {
                      countColor = isSelected
                          ? selectedColor
                          : (isIn ? Colors.redAccent : Colors.indigoAccent);
                    } else {
                      countColor = isSelected ? selectedColor : _Palette.dark.withOpacity(.75);
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: isSelected ? 22 : 18,
                            fontWeight: FontWeight.bold,
                            color: countColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(pageInfo.title, style: labelStyle),
                      ],
                    );
                  },
                ),
                label: '',
              );
            },
          ),
        );
      },
    );
  }

  Future<int> _countForType(PlateType type) async {
    final db = await OfflineAuthDb.instance.database;
    final key = _statusTypeKey(type);

    final res = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${OfflineAuthDb.tablePlates} WHERE COALESCE(status_type, \'\') = ?',
      [key],
    );
    final c = (res.isNotEmpty ? res.first['c'] : 0) as int? ?? 0;
    return c;
  }

  String _statusTypeKey(PlateType type) => type.name;
}
