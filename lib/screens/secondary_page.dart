import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/secondary/secondary_state.dart';
import '../states/secondary/secondary_mode.dart';
import '../states/user/user_state.dart';
import '../states/secondary/secondary_info.dart';

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
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          centerTitle: true,
          title: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_ios, size: 16, color: Colors.grey),
              SizedBox(width: 4),
              Text(
                " 업무 현황 | 비어 있음 ",
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
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
