import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바


class Calender extends StatelessWidget {
  const Calender({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: const Center(
        child: Text('Calender Page'), // 본문
      ),
      bottomNavigationBar: const SecondaryMiniNavigation( // 하단 내비게이션
        icons: [
          Icons.today_outlined, // to do 추가
          Icons.delete, // to do 삭제
          Icons.question_mark,
        ],
      ),
    );
  }
}