import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바

class LocationManagement extends StatelessWidget {
  const LocationManagement({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: const Center(
        child: Text('LocationManagement Page'), // 본문
      ),
      bottomNavigationBar: const SecondaryMiniNavigation(
        // 하단 내비게이션
        icons: [
          Icons.add, // 구역 추가 아이콘
          Icons.delete, // 구역 삭제 아이콘
          Icons.question_mark, // 미정 아이콘
        ],
      ),
    );
  }
}
