import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/secondary/secondary_state.dart';
import '../states/secondary/secondary_mode.dart';
import '../states/user/user_state.dart';
import '../states/secondary/secondary_info.dart';
import '../widgets/navigation/secondary_role_navigation.dart';

class SecondaryPage extends StatelessWidget {
  const SecondaryPage({super.key});

  /// 모드 → 페이지 매핑을 Map으로 단순화
  /// (필요 시 권한별 필터링은 userRole을 사용해 확장 가능)
  static final Map<ModeStatus, List<SecondaryInfo>> _pagesByMode = {
    ModeStatus.managerField: managerFieldModePages,
    ModeStatus.lowMiddleManage: lowMiddleManagePages,
    ModeStatus.highManage: highManagePages,
    ModeStatus.dev: devPages,
    ModeStatus.lowField: lowUserModePages,
    ModeStatus.middleField: middleUserModePages,
    ModeStatus.highField: highUserModePages,
    ModeStatus.admin: adminPages,
  };

  /// 현재 모드와 사용자 역할을 기반으로 페이지 집합을 구합니다.
  /// (지금은 권한 제한을 적용하지 않고, 필요 시 userRole을 사용해 조건을 추가하세요)
  static List<SecondaryInfo> getUpdatedPages(
      String userRole,
      SecondaryMode roleState,
      ) {
    final pages = _pagesByMode[roleState.currentStatus] ?? lowUserModePages;

    // 예: admin 권한이 아닐 때 admin 모드 차단을 원하면 아래를 사용
    // if (roleState.currentStatus == ModeStatus.admin && userRole != 'admin') {
    //   return lowUserModePages;
    // }

    return pages;
  }

  /// SecondaryInfo에 값 동등성(==/hashCode)이 없을 수 있으므로
  /// 제목(title) 기준으로 리스트 동등성을 비교하는 보조 함수
  static bool _samePagesByTitle(List<SecondaryInfo> a, List<SecondaryInfo> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].title != b[i].title) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SecondaryMode()),
        // ✅ UserState 변경에도 반응하도록 ProxyProvider2 사용
        ChangeNotifierProxyProvider2<SecondaryMode, UserState, SecondaryState>(
          create: (_) => SecondaryState(pages: lowUserModePages),
          update: (_, roleState, userState, secondaryState) {
            final newPages = getUpdatedPages(userState.role, roleState);

            // SecondaryInfo에 값 동등성이 없다면 listEquals가 의미가 약할 수 있으므로
            // 제목 기반 비교를 우선 사용
            final pagesUnchanged =
            _samePagesByTitle(secondaryState!.pages, newPages);

            if (!pagesUnchanged) {
              secondaryState.updatePages(newPages, keepIndex: true);
            }
            return secondaryState;
          },
        ),
      ],
      // ✅ key 전달(아래 설명 참고)
      child: const _SecondaryScaffold(key: ValueKey('secondary_scaffold')),
    );
  }
}

class _SecondaryScaffold extends StatelessWidget {
  const _SecondaryScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        centerTitle: true,
        title: SizedBox(
          height: kToolbarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SecondaryRoleNavigation(
                  onModeChanged: (selectedLabel) {
                    final manageState = context.read<SecondaryMode>();
                    final newMode =
                    ModeStatusExtension.fromLabel(selectedLabel);

                    // ✅ 여기서는 모드만 변경합니다.
                    // 페이지 리스트 갱신은 ProxyProvider2의 update가 맡습니다.
                    if (newMode != null &&
                        newMode != manageState.currentStatus) {
                      manageState.changeStatus(newMode);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: const RefreshableBody(),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PageBottomNavigation(),
            // ⬇️ DebugTriggerBar 대신 펠리컨 이미지 삽입 (네비게이션 바 아래)
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
    );
  }
}

class RefreshableBody extends StatelessWidget {
  const RefreshableBody({super.key});

  @override
  Widget build(BuildContext context) {
    // 불필요한 최상단 GestureDetector 제거(의미 없는 핸들러였음)
    return Consumer<SecondaryState>(
      builder: (context, state, child) {
        return Stack(
          children: [
            IndexedStack(
              index: state.selectedIndex,
              children: state.pages.map((pageInfo) {
                // ✅ 상태 보존 강화를 위해 안정적인 Key 부여
                return KeyedSubtree(
                  key: PageStorageKey<String>('secondary_${pageInfo.title}'),
                  child: pageInfo.page,
                );
              }).toList(),
            ),
            // ✅ 로딩 전환 부드럽게, 입력 차단
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !state.isLoading,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PageBottomNavigation extends StatelessWidget {
  const PageBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SecondaryState>(
      builder: (context, state, child) {
        return BottomNavigationBar(
          currentIndex: state.selectedIndex,
          onTap: state.onItemTapped,
          items: state.pages.map((pageInfo) {
            return BottomNavigationBarItem(
              icon: pageInfo.icon,
              label: pageInfo.title,
            );
          }).toList(),
          selectedItemColor: Colors.green,
          unselectedItemColor: Colors.purple,
          backgroundColor: Colors.white,
          elevation: 0, // 그림자 제거(아래 이미지가 그늘지지 않도록)
        );
      },
    );
  }
}

// ✅ DebugTriggerBar 위젯은 더 이상 사용하지 않으므로 제거되었습니다.
