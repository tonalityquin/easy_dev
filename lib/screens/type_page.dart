import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../states/page_state.dart';
import '../states/page_info.dart';
import '../screens/input_pages/input_3_digit.dart';

/// TypePage : 페이지 전환 및 UI 구성
class TypePage extends StatelessWidget {
  const TypePage({super.key});

  Future<void> _refreshData(BuildContext context) async {
    final pageState = Provider.of<PageState>(context, listen: false);
    pageState.setLoading(true); // 로딩 상태 활성화
    await pageState.refreshData(); // 데이터 갱신 메서드 호출
    pageState.setLoading(false); // 로딩 상태 비활성화
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PageState(pages: defaultPages),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.selectedItemColor,
        ),
        body: RefreshableBody(onRefresh: () => _refreshData(context)),
        bottomNavigationBar: const PageBottomNavigation(),
      ),
    );
  }
}

/// 재사용 가능한 Body 위젯
class RefreshableBody extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const RefreshableBody({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const Input3Digit()),
          );
        }
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
              if (state.isLoading)
                const Center(
                  child: CircularProgressIndicator(), // 로딩 표시 추가
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 재사용 가능한 BottomNavigationBar 위젯
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
