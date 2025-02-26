import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바


class Wireless extends StatelessWidget {
  const Wireless({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: const Center(
        child: Text('Wireless Page'), // 본문
      ),
      bottomNavigationBar: const SecondaryMiniNavigation( // 하단 내비게이션
        icons: [
          Icons.search, // 검색 아이콘
          Icons.person, // 프로필 아이콘
          Icons.sort, // 정렬 아이콘
        ],
      ),
    );
  }
}