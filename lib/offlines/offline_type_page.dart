import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../enums/plate_type.dart';

import 'offline_states/page/offline_page_state.dart';
import 'offline_states/page/offline_page_info.dart';

import '../screens/input_package/input_plate_screen.dart';
import 'offline_type_package/common_widgets/dashboard_bottom_sheet/offline_home_dash_board_bottom_sheet.dart';
import '../utils/snackbar_helper.dart';

// ▼ SQLite / 세션 (경로는 프로젝트에 맞게 조정하세요)
import 'sql/offline_auth_db.dart';        // ← 경로 조정
import 'sql/offline_auth_service.dart';   // ← 경로 조정

/// Deep Blue 팔레트(서비스 카드와 동일 계열)
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const fg = Color(0xFFFFFFFF); // 전경(흰색)
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
    // ✅ 진입 시 DB 워밍업
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
            // ✅ 이 화면에서만 뒤로가기(pop) 차단 → 앱 종료 방지
            canPop: false,
            // 뒤로가기를 시도했지만 팝이 막힌 경우(didPop=false)에만 선택 해제 로직 수행(오프라인/SQLite)
            onPopInvoked: (didPop) async {
              if (didPop) return; // 실제로 팝된 경우는 없음(canPop:false)

              final currentPage = pageState.pages[pageState.selectedIndex];
              final type = currentPage.collectionKey;
              await _unselectOneIfAnyFor(type);
              // ☆ 여기서 스낵바 안내는 하지 않음(요청사항)
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

  /// 현재 컬렉션(PlateType)에 대해 선택된 한 건이 있으면 해제 (is_selected=0).
  /// - status_type 매칭(기본: PlateType.name)이 가능한 경우 우선 적용
  /// - 세션 정보(선택자)로 더 좁히고, 없으면 넓게 해제
  Future<void> _unselectOneIfAnyFor(PlateType type) async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();

    final uid = (session?.userId ?? '').trim();
    final uname = (session?.name ?? '').trim();
    final statusKey = _statusTypeKey(type);

    await db.transaction((txn) async {
      // 후보 1개 찾기(가장 최근 갱신 순)
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

      // 우선 좁은 조건으로 시도
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
        // 못 찾으면 status_type 기준만으로 재시도
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

  String _statusTypeKey(PlateType type) {
    // 프로젝트 매핑 규칙에 맞게 조정하세요.
    // 기본값: enum 이름을 그대로 status_type과 매칭
    return type.name; // e.g., 'inRequest', 'outRequest' 등
  }
}

class _ChatDashboardBar extends StatelessWidget {
  const _ChatDashboardBar();

  // ‘다시 듣기’ 버튼 유지(외부 TTS/메시지 서비스 없이 안내만)
  static Future<void> _onReplayLatestPressed(BuildContext context) async {
    showSelectedSnackbar(context, '다시 듣기 기능이 비활성화되어 있습니다.');
  }

  // 현재 세션의 area 추출 (없으면 빈 문자열)
  static Future<String> _loadCurrentArea() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

    // 우선 userId로 조회, 없으면 isSelected=1 계정 사용
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

    final area = ((row?['currentArea'] as String?) ??
        (row?['selectedArea'] as String?) ??
        '')
        .trim();
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
              // ── 채팅: '다시 듣기' 버튼만 유지 (외부 서비스 접근 없음)
              Expanded(
                child: ElevatedButton(
                  onPressed: enabled ? () => _onReplayLatestPressed(context) : null,
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
                      Icon(Icons.volume_up, size: 20),
                      SizedBox(width: 6),
                      Text('다시 듣기', overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // ── 대시보드(기존)
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

class RefreshableBody extends StatefulWidget {
  const RefreshableBody({super.key});

  @override
  State<RefreshableBody> createState() => _RefreshableBodyState();
}

class _RefreshableBodyState extends State<RefreshableBody> {
  // ── 가로 스와이프(좌/우 페이지 전환)
  double _dragDistance = 0.0;

  // 임계값
  static const double _hDistanceThreshold = 80.0;
  static const double _hVelocityThreshold = 1000.0;

  void _handleHorizontalDragEnd(BuildContext context, double velocity) {
    if (_dragDistance > _hDistanceThreshold && velocity > _hVelocityThreshold) {
      Navigator.of(context).push(_slidePage(const InputPlateScreen(), fromLeft: true));
    } else if (_dragDistance < -_hDistanceThreshold && velocity < -_hVelocityThreshold) {
      // ⛔ 제거됨: SecondaryPage로의 이동 로직
      debugPrint('⏸[H] 좌->우 이외 스와이프는 현재 동작 없음');
    } else {
      debugPrint('⏸[H] 거리(${_dragDistance.toStringAsFixed(1)})/속도($velocity) 부족 → 무시');
    }
    _dragDistance = 0.0;
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

      // ── 가로 스와이프(좌/우 페이지 전환)
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(
        context,
        details.primaryVelocity ?? 0,
      ),

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
    // 팔레트 기반 선택/비선택 색
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
            // 탭 전환 시 재빌드로 FutureBuilder가 다시 카운트합니다.
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
                    mainAxisSize: MainAxisSize.min, // ★ overflow 방지
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

              // ✅ PlateState 의존 제거 → SQLite 카운트로 대체
              return BottomNavigationBarItem(
                icon: FutureBuilder<int>(
                  future: _countForType(type),
                  builder: (context, snap) {
                    final count = snap.data ?? 0;

                    // 입차/출차 숫자 색
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
                      mainAxisSize: MainAxisSize.min, // ★ overflow 방지
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

    // 프로젝트 규칙에 맞게 WHERE 조건을 조정하세요.
    // 기본은 status_type = PlateType.name 로 카운트
    final res = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${OfflineAuthDb.tablePlates} WHERE COALESCE(status_type, \'\') = ?',
      [key],
    );
    final c = (res.isNotEmpty ? res.first['c'] : 0) as int? ?? 0;
    return c;
  }

  String _statusTypeKey(PlateType type) => type.name;
}
