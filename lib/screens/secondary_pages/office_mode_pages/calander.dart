import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 하단 내비게이션 바


class Calander extends StatelessWidget {
  const Calander({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryMiniNavigation(), // 상단 내비게이션
      body: const Center(
        child: Text('Calander Page'), // 본문
      ),
      bottomNavigationBar: const SecondaryRoleNavigation( // 하단 내비게이션
        icons: [
          Icons.today_outlined, // to do 추가
          Icons.delete, // to do 삭제
          Icons.question_mark,
        ],
      ),
    );
  }
}