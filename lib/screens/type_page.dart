import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart'; // 앱 색상 팔레트
import '../utils/show_snackbar.dart';
import '../states/page_state.dart'; // 페이지 상태 관리 클래스
import '../states/page_info.dart'; // 페이지 정보 관리 클래스
import '../screens/input_pages/input_3_digit.dart'; // 3자리 입력 페이지
import 'secondary_page.dart'; // SecondaryPage

/// 다양한 타입의 페이지를 탐색할 수 있는 기본 화면
class TypePage extends StatelessWidget {
  const TypePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // PageState 상태 제공
      create: (_) => PageState(pages: defaultPages),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.selectedItemColor, // 선택된 아이템 색상
        ),
        body: const RefreshableBody(), // 수평 드래그 동작이 가능한 본문 위젯
        bottomNavigationBar: const PageBottomNavigation(), // 하단 내비게이션
      ),
    );
  }
}

/// 본문 위젯
/// - 수평 드래그를 통해 페이지 전환 가능
/// - 상태 관리 및 로딩 상태 표시
class RefreshableBody extends StatelessWidget {
  const RefreshableBody({super.key});

  /// 드래그 동작 처리
  /// - 오른쪽 드래그: Input3Digit 페이지로 이동
  /// - 왼쪽 드래그: SecondaryPage로 이동
  void _handleDrag(BuildContext context, double velocity) {
    if (velocity > 0) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const Input3Digit()),
      );
    } else if (velocity < 0) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SecondaryPage()),
      );
    } else {
      showSnackbar(context, '드래그 동작이 감지되지 않았습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 수평 드래그 종료 시 `_handleDrag` 호출
      onHorizontalDragEnd: (details) {
        _handleDrag(context, details.primaryVelocity ?? 0);
      },
      child: Consumer<PageState>(
        builder: (context, state, child) {
          return Stack(
            children: [
              // 현재 선택된 페이지를 표시
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

/// 하단 내비게이션 바
/// - 페이지 전환을 관리
class PageBottomNavigation extends StatelessWidget {
  const PageBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PageState>(
      builder: (context, state, child) {
        return BottomNavigationBar(
          currentIndex: state.selectedIndex,
          // 현재 선택된 페이지 인덱스
          onTap: state.onItemTapped,
          // 페이지 전환 처리
          items: state.pages.map((pageInfo) {
            return BottomNavigationBarItem(
              icon: Icon(pageInfo.iconData), // ✅ IconData를 Icon으로 변경
              label: pageInfo.title, // 페이지 타이틀
            );
          }).toList(),
          selectedItemColor: Colors.red,
          // 선택된 아이템 색상
          unselectedItemColor: Colors.blue,
          // 선택되지 않은 아이템 색상
          backgroundColor: Colors.white, // 배경 색상
        );
      },
    );
  }
}
