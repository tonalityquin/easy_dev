import 'package:flutter/foundation.dart'; // listEquals 사용
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/secondary/secondary_state.dart';
import '../states/secondary/secondary_mode.dart';
import '../states/user/user_state.dart';
import '../states/secondary/secondary_info.dart';
import '../widgets/navigation/secondary_role_navigation.dart';

class SecondaryPage extends StatelessWidget {
  const SecondaryPage({super.key});

  /// ✅ 역할에 따른 페이지 구성 함수 (바텀시트에서도 접근 가능하게 static 처리)
  static List<SecondaryInfo> getUpdatedPages(String userRole, SecondaryMode roleState) {
    final mode = roleState.currentStatus;

    switch (mode) {
      case ModeStatus.managerField:
        return managerFieldModePages;
      case ModeStatus.lowMiddleManage:
        return lowMiddleManagePages;
      case ModeStatus.highManage:
        return highManagePages;
      case ModeStatus.dev:
        return devPages;
      case ModeStatus.lowField:
        return lowUserModePages;
      case ModeStatus.middleField:
        return middleUserModePages;
      case ModeStatus.highField:
        return highUserModePages;
      case ModeStatus.admin:
        return adminPages;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ watch → read 로 변경하여 UserState 변경 시 전체 리빌드 방지
    final userRole = context.read<UserState>().role;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SecondaryMode()),
        ChangeNotifierProxyProvider<SecondaryMode, SecondaryState>(
          create: (_) => SecondaryState(pages: lowUserModePages),
          update: (_, roleState, secondaryState) {
            final newPages = getUpdatedPages(userRole, roleState);

            // ✅ 페이지 구성이 동일하면 불필요한 업데이트/리빌드 방지
            if (listEquals(secondaryState!.pages, newPages)) {
              return secondaryState;
            }

            // ✅ 인덱스 보존(필요 시 keepIndex/preserveIndex 옵션 맞춰 사용)
            secondaryState.updatePages(newPages, keepIndex: true);
            return secondaryState;
          },
        ),
      ],
      child: Scaffold(
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
                      final manageState = Provider.of<SecondaryMode>(context, listen: false);
                      // 여기서도 read 사용
                      final userRole = Provider.of<UserState>(context, listen: false).role;
                      final newMode = ModeStatusExtension.fromLabel(selectedLabel);

                      if (newMode != null && newMode != manageState.currentStatus) {
                        // ✅ 실제 모드가 바뀔 때만 변경
                        manageState.changeStatus(newMode);

                        final newPages = getUpdatedPages(userRole, manageState);
                        // ✅ 인덱스 보존하여 불필요한 탭 초기화 방지
                        Provider.of<SecondaryState>(context, listen: false).updatePages(newPages, keepIndex: true);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        body: const RefreshableBody(),
        bottomNavigationBar: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PageBottomNavigation(),
            DebugTriggerBar(),
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
    return GestureDetector(
      onHorizontalDragEnd: (details) {},
      child: Consumer<SecondaryState>(
        builder: (context, state, child) {
          return Stack(
            children: [
              IndexedStack(
                index: state.selectedIndex,
                children: state.pages.map((pageInfo) => pageInfo.page).toList(),
              ),
              if (state.isLoading)
                const Center(
                  child: CircularProgressIndicator(),
                ),
            ],
          );
        },
      ),
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
        );
      },
    );
  }
}

class DebugTriggerBar extends StatelessWidget {
  const DebugTriggerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        color: Colors.transparent,
      ),
    );
  }
}
