import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart'; // 앱의 색상 팔레트 정의
import '../states/page_state.dart'; // 페이지 상태 관리 클래스
import '../states/page_info.dart'; // 페이지 정보를 포함하는 클래스
import '../screens/input_pages/input_3_digit.dart'; // 3자리 입력 페이지
import 'secondary_page.dart';

/// TypePage 위젯
/// 다양한 타입 페이지를 탐색할 수 있는 기본 화면.
class TypePage extends StatelessWidget {
  const TypePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // PageState 제공자로 초기화
      create: (_) => PageState(pages: defaultPages),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.selectedItemColor, // 선택된 아이템의 색상
        ),
        body: const RefreshableBody(), // RefreshableBody에서 onRefresh 제거
        bottomNavigationBar: const PageBottomNavigation(),
      ),
    );
  }
}

/// RefreshableBody 위젯
/// 본문 위젯, 수평 드래그 동작 처리 및 상태 표시.
class RefreshableBody extends StatelessWidget {
  const RefreshableBody({super.key});

  /// 드래그 동작 처리
  /// [context] 빌드 컨텍스트
  /// [velocity] 드래그 속도
  void _handleDrag(BuildContext context, double velocity) {
    if (velocity > 0) {
      // 오른쪽 드래그 시 Input3Digit 페이지로 이동
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const Input3Digit()),
      );
    } else if (velocity < 0) {
      // 왼쪽 드래그 시 SecondaryPage로 이동
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SecondaryPage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('드래그 동작이 감지되지 않았습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 수평 드래그 종료 시 동작
      onHorizontalDragEnd: (details) {
        _handleDrag(context, details.primaryVelocity ?? 0);
      },
      child: Consumer<PageState>(
        // PageState 상태를 사용
        builder: (context, state, child) {
          return Stack(
            children: [
              // 현재 선택된 페이지 표시
              IndexedStack(
                index: state.selectedIndex,
                children: state.pages.map((pageInfo) => pageInfo.page).toList(),
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
/// 하단 내비게이션 바, 페이지 전환 관리.
class PageBottomNavigation extends StatelessWidget {
  const PageBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PageState>(
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
          selectedItemColor: Colors.red,
          // 선택된 아이템의 색상
          unselectedItemColor: Colors.blue,
          // 선택되지 않은 아이템의 색상
          backgroundColor: Colors.white, // 바의 배경 색상
        );
      },
    );
  }
}
