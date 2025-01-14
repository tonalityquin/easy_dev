import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 하단 내비게이션 바


class Chat extends StatelessWidget {
  const Chat({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryMiniNavigation(), // 상단 내비게이션
      body: const Center(
        child: Text('Chat Page'), // 본문
      ),
      bottomNavigationBar: const SecondaryRoleNavigation( // 하단 내비게이션
        icons: [
          Icons.search, // 검색 아이콘
          Icons.person, // 프로필 아이콘
          Icons.sort, // 정렬 아이콘
        ],
      ),
    );
  }
}