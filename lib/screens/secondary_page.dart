import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../states/secondary/secondary_state.dart';
import '../states/secondary/secondary_access_state.dart';
import '../states/user/user_state.dart';
import '../states/secondary/secondary_info.dart';

class SecondaryPage extends StatelessWidget {
  const SecondaryPage({super.key});

  List<SecondaryInfo> _getUpdatedPages(String userRole, SecondaryAccessState roleState) {
    if (userRole == 'User') {
      return fieldModePages;
    } else {
      switch (roleState.currentStatus) {
        case 'Field Mode':
          return fieldModePages;
        case 'Office Mode':
          return officeModePages;
        case 'Statistics Mode':
          return statisticsPages;
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
        ChangeNotifierProvider(create: (_) => SecondaryAccessState()),
        ChangeNotifierProxyProvider<SecondaryAccessState, SecondaryState>(
          create: (_) => SecondaryState(pages: fieldModePages),
          update: (_, roleState, secondaryState) {
            final newPages = _getUpdatedPages(userRole, roleState);
            return secondaryState!..updatePages(newPages);
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.selectedItemColor,
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
