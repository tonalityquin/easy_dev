import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart'; // 앱의 색상 팔레트 정의
import '../states/secondary_state.dart'; // 페이지 상태 관리 클래스
import '../states/secondary_access_state.dart'; // 모드 상태 관리 클래스
import '../states/user_state.dart'; // 사용자 상태 관리 클래스
import '../states/secondary_info.dart'; // 페이지 정보를 포함하는 클래스

/// SecondaryPage 위젯
/// 다양한 타입 페이지를 탐색할 수 있는 기본 화면.
class SecondaryPage extends StatelessWidget {
  const SecondaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>(); // UserState를 통해 사용자 상태 가져오기
    final userRole = userState.role; // Role 가져오기

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SecondaryAccessState()), // Role 상태 관리
        ChangeNotifierProxyProvider<SecondaryAccessState, SecondaryState>(
          create: (_) => SecondaryState(pages: fieldModePages), // 초기 Field Mode 페이지
          update: (_, roleState, secondaryState) {
            // Role 상태 변화에 따라 페이지 업데이트
            final newPages = userRole == 'User'
                ? fieldModePages
                : (roleState.currentStatus == 'Field Mode' ? fieldModePages : officeModePages);
            return secondaryState!..updatePages(newPages);
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.selectedItemColor, // 선택된 아이템의 색상
        ),
        body: const RefreshableBody(), // RefreshableBody에서 onRefresh 제거
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

/// RefreshableBody 위젯
/// 새로 고침 가능한 본문 위젯 (onRefresh 제거 후 수정).
class RefreshableBody extends StatelessWidget {
  const RefreshableBody({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 수평 드래그 종료 시 동작
      onHorizontalDragEnd: (details) {
        // `Input3Digit`으로 스와이프하는 코드는 삭제되었습니다.
      },
      child: Consumer<SecondaryState>(
        // SecondaryState 상태를 사용
        builder: (context, state, child) {
          return Stack(
            children: [
              // 현재 선택된 페이지 표시
              IndexedStack(
                index: state.selectedIndex,
                children: state.pages
                    .map((pageInfo) => pageInfo.page) // 각 SecondaryInfo 표시
                    .toList(),
              ),
              // 로딩 상태 표시
              if (state.isLoading)
                const Center(
                  child: CircularProgressIndicator(), // 로딩 스피너
                ),
            ],
          );
        },
      ),
    );
  }
}

/// PageBottomNavigation 위젯
/// 하단 내비게이션 바로, 페이지 전환 관리.
class PageBottomNavigation extends StatelessWidget {
  const PageBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SecondaryState>(
      // PageState를 사용하여 현재 상태 및 페이지 정보에 접근
      builder: (context, state, child) {
        return BottomNavigationBar(
          currentIndex: state.selectedIndex,
          // 현재 선택된 페이지의 인덱스
          onTap: state.onItemTapped,
          // 특정 페이지 탭 시 호출
          items: state.pages.map((pageInfo) {
            return BottomNavigationBarItem(
              icon: pageInfo.icon, // 페이지 아이콘
              label: pageInfo.title, // 페이지 타이틀
            );
          }).toList(),
          selectedItemColor: Colors.green,
          // 선택된 아이템의 색상
          unselectedItemColor: Colors.purple,
          // 선택되지 않은 아이템의 색상
          backgroundColor: Colors.white, // 바의 배경 색상
        );
      },
    );
  }
}
