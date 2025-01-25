import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart'; // 앱 색상 팔레트
import '../states/secondary_state.dart'; // 페이지 상태 관리
import '../states/secondary_access_state.dart'; // Role 상태 관리
import '../states/user_state.dart'; // 사용자 상태 관리
import '../states/secondary_info.dart'; // 페이지 정보 관리 클래스

/// SecondaryPage
/// - Role과 페이지 상태에 따라 다양한 타입의 페이지를 탐색할 수 있는 기본 화면
class SecondaryPage extends StatelessWidget {
  const SecondaryPage({super.key});

  /// 사용자 Role 및 Role 상태에 따른 페이지 업데이트 로직
  List<SecondaryInfo> _getUpdatedPages(String userRole, SecondaryAccessState roleState) {
    if (userRole == 'User') {
      return fieldModePages; // 일반 사용자에게는 Field Mode Pages 제공
    } else {
      // Role 상태에 따라 Field Mode 또는 Office Mode 제공
      return roleState.currentStatus == 'Field Mode' ? fieldModePages : officeModePages;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>(); // 사용자 상태 가져오기
    final userRole = userState.role; // 사용자 Role 확인

    return MultiProvider(
      providers: [
        // Role 상태 관리
        ChangeNotifierProvider(create: (_) => SecondaryAccessState()),
        // Role 상태에 따라 페이지 상태 동적 업데이트
        ChangeNotifierProxyProvider<SecondaryAccessState, SecondaryState>(
          create: (_) => SecondaryState(pages: fieldModePages),
          update: (_, roleState, secondaryState) {
            final newPages = _getUpdatedPages(userRole, roleState); // 상태 업데이트 함수 호출
            return secondaryState!..updatePages(newPages);
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.selectedItemColor, // 선택된 아이템 색상
        ),
        body: const RefreshableBody(), // 새로 고침 가능한 본문 위젯
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            PageBottomNavigation(), // 하단 내비게이션 바
          ],
        ),
      ),
    );
  }
}

/// RefreshableBody
/// - 현재 선택된 페이지와 로딩 상태를 표시하는 본문 위젯
class RefreshableBody extends StatelessWidget {
  const RefreshableBody({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // `Input3Digit`으로 스와이프 동작 제거됨
      },
      child: Consumer<SecondaryState>(
        builder: (context, state, child) {
          // 상태가 null이 될 가능성이 없으므로 null 체크 제거
          return Stack(
            children: [
              // 선택된 페이지 표시
              IndexedStack(
                index: state.selectedIndex,
                children: state.pages.map((pageInfo) => pageInfo.page).toList(),
              ),
              // 로딩 상태 표시
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

/// PageBottomNavigation
/// - 하단 내비게이션 바를 통해 페이지 전환 관리
class PageBottomNavigation extends StatelessWidget {
  const PageBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SecondaryState>(
      builder: (context, state, child) {
        return BottomNavigationBar(
          currentIndex: state.selectedIndex,
          // 현재 선택된 페이지 인덱스
          onTap: state.onItemTapped,
          // 페이지 탭 처리
          items: state.pages.map((pageInfo) {
            return BottomNavigationBarItem(
              icon: pageInfo.icon, // 페이지 아이콘
              label: pageInfo.title, // 페이지 타이틀
            );
          }).toList(),
          selectedItemColor: Colors.green,
          // 선택된 아이템 색상
          unselectedItemColor: Colors.purple,
          // 선택되지 않은 아이템 색상
          backgroundColor: Colors.white, // 배경 색상
        );
      },
    );
  }
}
