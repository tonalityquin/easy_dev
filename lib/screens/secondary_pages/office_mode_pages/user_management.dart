import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 하단 내비게이션 바


class UserManagement extends StatelessWidget {
  const UserManagement({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryMiniNavigation(), // 상단 내비게이션
      body: const Center(
        child: Text('UserManagement Page'), // 본문
      ),
      bottomNavigationBar: const SecondaryRoleNavigation( // 하단 내비게이션
        icons: [
          Icons.add, // 유저 추가 아이콘
          Icons.delete, // 유저 삭제 아이콘
          Icons.verified_user, // 유저 수정 아이콘
        ],
      ),
    );
  }
}