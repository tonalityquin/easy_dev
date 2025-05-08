import 'package:flutter/material.dart';
import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart'; // 하단 내비게이션 바

class Headquarter extends StatelessWidget {
  const Headquarter({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TopNavigation(), // ✅ title로만 사용
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const Center(
        child: Text('Headquarter'),
      ),
      bottomNavigationBar: const HqMiniNavigation(
        height: 56,
        iconSize: 22,
        icons: [
          Icons.dashboard,     // 대시보드
          Icons.analytics,     // 분석
          Icons.settings,      // 설정
        ],
        labels: [
          'Dashboard',
          'Analytics',
          'Settings',
        ],

      ),
    );
  }
}
