import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart'; // 앱의 색상 팔레트 정의
import '../states/page_state.dart'; // 페이지 상태 관리 클래스
import '../states/page_info.dart'; // 페이지 정보를 포함하는 클래스
import '../screens/input_pages/input_3_digit.dart'; // 3자리 입력 페이지
import 'secondary_page.dart';

class TypePage extends StatelessWidget {
  const TypePage({super.key});

  /// 데이터 갱신 처리
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
        appBar: AppBar(
          backgroundColor: AppColors.selectedItemColor, // 선택된 아이템의 색상
        ),
        body: RefreshableBody(onRefresh: () => _refreshData(context)),
        bottomNavigationBar: const PageBottomNavigation(),
      ),
    );
  }
}

class RefreshableBody extends StatelessWidget {
  final Future<void> Function() onRefresh; // 새로 고침 함수

  const RefreshableBody({super.key, required this.onRefresh});

  /// 드래그 동작 처리
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
        builder: (context, state, child) {
          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: onRefresh,
                child: IndexedStack(
                  index: state.selectedIndex,
                  children: state.pages.map((pageInfo) => pageInfo.page).toList(),
                ),
              ),
              if (state.isLoading) const Center(child: CircularProgressIndicator()), // 로딩 스피너
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
    return Consumer<PageState>(
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
          selectedItemColor: Colors.red,
          unselectedItemColor: Colors.blue,
          backgroundColor: Colors.white,
        );
      },
    );
  }
}
