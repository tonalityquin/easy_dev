import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../states/page_state.dart';
import '../screens/input_pages/input_3_digit.dart';

/// TypePage : 페이지 전환 및 UI 구성
class TypePage extends StatelessWidget {
  const TypePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PageState(), // 상태 주입
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
          child: Consumer<PageState>(
            builder: (context, state, child) {
              return IndexedStack(
                index: state.selectedIndex, // 선택된 페이지 렌더링
                children: state.pages,
              );
            },
          ),
        ),
        bottomNavigationBar: Consumer<PageState>(
          builder: (context, state, child) {
            return BottomNavigationBar(
              currentIndex: state.selectedIndex,
              onTap: state.onItemTapped,
              // 탭 클릭 이벤트
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.directions_car),
                  label: '입차 요청',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.check_circle),
                  label: '입차 완료',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.departure_board),
                  label: '출차 요청',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.done_all),
                  label: '출차 완료',
                ),
              ],
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
