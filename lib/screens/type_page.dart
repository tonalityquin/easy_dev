import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../states/page_state.dart';
import '../states/page_info.dart'; // 페이지 정보 가져오기
import '../screens/input_pages/input_3_digit.dart';

/// TypePage : 페이지 전환 및 UI 구성
class TypePage extends StatelessWidget {
  const TypePage({super.key});

  Future<void> _refreshData(BuildContext context) async {
    final pageState = Provider.of<PageState>(context, listen: false);
    await pageState.refreshData(); // PageState의 데이터 갱신 메서드 호출
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PageState(pages: defaultPages), // 상태 주입 시 pages 전달
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.selectedItemColor,
        ),
        body: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
              // 우측 스와이프 시 Input3DigitPage로 이동
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const Input3Digit()),
              );
            }
          },
          child: RefreshIndicator(
            onRefresh: () => _refreshData(context), // 데이터 갱신 메서드 호출
            child: Consumer<PageState>(
              builder: (context, state, child) {
                return IndexedStack(
                  index: state.selectedIndex, // 선택된 페이지 렌더링
                  children: state.pages.map((pageInfo) => pageInfo.page).toList(),
                );
              },
            ),
          ),
        ),
        bottomNavigationBar: Consumer<PageState>(
          builder: (context, state, child) {
            return BottomNavigationBar(
              currentIndex: state.selectedIndex,
              onTap: state.onItemTapped, // 탭 클릭 이벤트
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
        ),
      ),
    );
  }
}
