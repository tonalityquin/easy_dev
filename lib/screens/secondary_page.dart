import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/secondary/secondary_state.dart';
import '../states/secondary/secondary_mode.dart';
import '../states/user/user_state.dart';
import '../states/secondary/secondary_info.dart';
import '../widgets/navigation/secondary_role_navigation.dart';

class SecondaryPage extends StatelessWidget {
  const SecondaryPage({super.key});

  List<SecondaryInfo> _getUpdatedPages(String userRole, SecondaryMode roleState) {
    if (userRole == 'User') {
      return fieldModePages;
    } else {
      switch (roleState.currentStatus) {
        case 'Field Mode':
          return fieldModePages;
        case 'Office Mode':
          return officeModePages;
        case 'Document Mode':
          return documentPages;
        default:
          return fieldModePages;
      }
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
          create: (_) => SecondaryState(pages: fieldModePages),
          update: (_, roleState, secondaryState) {
            final newPages = _getUpdatedPages(userRole, roleState);
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
              children: const [
                Flexible(
                  child: SecondaryRoleNavigation(), // 여기를 Flexible로 감쌈
                ),
              ],
            ),
          ),
        ),
        body: const RefreshableBody(),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            PageBottomNavigation(),
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
