import 'dart:async';
import 'package:flutter/material.dart';

import '../../../widgets/navigation/navigation_hq_mini.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'management_package/field.dart';
import 'management_package/statistics.dart';

/// Deep Blue Palette
class _Palette {
  static const base  = Color(0xFF0D47A1); // primary
  static const dark  = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 톤 변형/보더
  static const fg    = Colors.white;      // 전경(아이콘/텍스트)
}

class Management extends StatefulWidget {
  const Management({super.key});

  @override
  State<Management> createState() => _ManagementState();
}

class _ManagementState extends State<Management> {
  int _selectedIndex = 0;

  final TextEditingController _controller = TextEditingController();

  StreamSubscription? _userSubscription;

  @override
  void dispose() {
    _userSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: _Palette.dark,
          surfaceTintColor: _Palette.light,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: _Palette.light.withOpacity(.25),
            ),
          ),
        ),
        body: _selectedIndex == 0
            ? const Statistics()
            : _selectedIndex == 1
            ? const Field()
            : const Center(child: Text('해당 탭의 콘텐츠는 준비 중입니다.')),
        bottomNavigationBar: Theme(
          // ⬇️ HqMiniNavigation에 Deep Blue 팔레트 주입
          data: baseTheme.copyWith(
            colorScheme: baseTheme.colorScheme.copyWith(
              primary: _Palette.base,
              secondary: _Palette.light,
              onPrimary: _Palette.fg,
              onSurface: _Palette.dark,
              surfaceTint: _Palette.light,
            ),
            iconTheme: IconThemeData(color: _Palette.dark.withOpacity(.80)),
            textTheme: baseTheme.textTheme.apply(
              bodyColor: _Palette.dark,
              displayColor: _Palette.dark,
            ),
          ),
          child: HqMiniNavigation(
            height: 56,
            iconSize: 22,
            currentIndex: _selectedIndex,
            icons: const [
              Icons.compare_arrows,
              Icons.directions_walk,
            ],
            labels: const [
              'InOut',
              'Field',
            ],
            onIconTapped: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
          ),
        ),
      ),
    );
  }
}
