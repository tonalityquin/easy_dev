import 'package:easydev/screens/hq_pages/hq_pages/hq_board.dart';
import 'package:easydev/screens/hq_pages/hq_pages/hq_chat.dart';
import 'package:flutter/material.dart';
import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart';


class Headquarter extends StatefulWidget {
  const Headquarter({super.key});

  @override
  State<Headquarter> createState() => _HeadquarterState();
}

class _HeadquarterState extends State<Headquarter> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: _selectedIndex == 0
            ? const HqBoard()
            : _selectedIndex == 1
            ? const HqChat() // ✅ 새로운 탭 연결
            : const Center(child: Text('해당 탭의 콘텐츠는 준비 중입니다.')),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          icons: const [
            Icons.today,
            Icons.input,
          ],
          labels: const [
            'HQ Board',
            'HQ Chat',
          ],
          onIconTapped: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      ),
    );
  }
}
