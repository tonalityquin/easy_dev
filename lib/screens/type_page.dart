import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart'; // 앱의 색상 팔레트 정의
import '../states/page_state.dart'; // 페이지 상태 관리 클래스
import '../states/page_info.dart'; // 페이지 정보를 포함하는 클래스
import '../screens/input_pages/input_3_digit.dart'; // 3자리 입력 페이지

/// TypePage 위젯
/// 여러 타입 페이지를 탐색할 수 있는 기본 화면.
/// PageState를 통해 상태 관리하며, 새로 고침 및 페이지 전환 기능 포함.
class TypePage extends StatelessWidget {
  const TypePage({super.key});

  /// 데이터를 새로 고침하는 함수
  /// [PageState]의 loading 상태를 설정하고 데이터를 갱신
  Future<void> _refreshData(BuildContext context) async {
    final pageState = Provider.of<PageState>(context, listen: false);
    pageState.setLoading(true); // 로딩 상태 활성화
    await pageState.refreshData(); // 데이터 갱신
    pageState.setLoading(false); // 로딩 상태 비활성화
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // PageState 제공자로 초기화
      create: (_) => PageState(pages: defaultPages),
      child: Scaffold(
        // 상단 앱바
        appBar: AppBar(
          backgroundColor: AppColors.selectedItemColor, // 선택된 아이템의 색상
        ),
        // 본문 영역
        body: RefreshableBody(onRefresh: () => _refreshData(context)), // 새로 고침 가능 본문
        // 하단 내비게이션 바
        bottomNavigationBar: const PageBottomNavigation(),
      ),
    );
  }
}

/// RefreshableBody 위젯
/// 새로 고침 가능한 본문으로, 수평 스와이프로 페이지 이동 가능.
class RefreshableBody extends StatelessWidget {
  final Future<void> Function() onRefresh; // 새로 고침 함수

  const RefreshableBody({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 수평 드래그 끝났을 때 동작
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          // 오른쪽 방향으로 드래그 시, Input3Digit 페이지로 이동
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const Input3Digit()),
          );
        }
      },
      child: Consumer<PageState>(
        // PageState의 상태를 사용
        builder: (context, state, child) {
          return Stack(
            children: [
              // 새로 고침 가능 영역
              RefreshIndicator(
                onRefresh: onRefresh, // onRefresh로 전달된 함수 실행
                child: IndexedStack(
                  // 현재 선택된 인덱스의 페이지 표시
                  index: state.selectedIndex,
                  children: state.pages.map((pageInfo) => pageInfo.page).toList(),
                ),
              ),
              // 로딩 중인 경우 프로그래스 표시
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

/// PageBottomNavigation 위젯
/// 하단 내비게이션 바로, 페이지 전환을 관리.
class PageBottomNavigation extends StatelessWidget {
  const PageBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PageState>(
      builder: (context, state, child) {
        return BottomNavigationBar(
          currentIndex: state.selectedIndex,
          // 현재 선택된 인덱스
          onTap: state.onItemTapped,
          // 탭했을 때의 동작
          items: state.pages.map((pageInfo) {
            return BottomNavigationBarItem(
              icon: pageInfo.icon, // 각 페이지 아이콘
              label: pageInfo.title, // 각 페이지 타이틀
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
