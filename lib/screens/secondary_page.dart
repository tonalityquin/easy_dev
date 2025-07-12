import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/secondary/secondary_state.dart';
import '../states/secondary/secondary_mode.dart';
import '../states/user/user_state.dart';
import '../states/secondary/secondary_info.dart';
import '../widgets/navigation/secondary_role_navigation.dart';
import 'secondary_pages/debugs/secondary_debug_bottom_sheet.dart';

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
    final userState = context.watch<UserState>();
    final userRole = userState.role;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SecondaryMode()),
        ChangeNotifierProxyProvider<SecondaryMode, SecondaryState>(
          create: (_) => SecondaryState(pages: lowUserModePages),
          update: (_, roleState, secondaryState) {
            final newPages = getUpdatedPages(userRole, roleState);
            return secondaryState!..updatePages(newPages);
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
                      final userRole = Provider.of<UserState>(context, listen: false).role;
                      final newMode = ModeStatusExtension.fromLabel(selectedLabel);
                      if (newMode != null) {
                        manageState.changeStatus(newMode);
                        final newPages = getUpdatedPages(userRole, manageState);
                        Provider.of<SecondaryState>(context, listen: false).updatePages(newPages);
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
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => const SecondaryDebugBottomSheet(),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        color: Colors.transparent,
        child: const Icon(
          Icons.bug_report,
          size: 20,
          color: Colors.grey,
        ),
      ),
    );
  }
}
