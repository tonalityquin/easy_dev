import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바


class Adjustment extends StatelessWidget {
  const Adjustment({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: const Center(
        child: Text('Adjustment Page'), // 본문
      ),
      bottomNavigationBar: const SecondaryMiniNavigation( // 하단 내비게이션
        icons: [
          Icons.add, // 정산 유형 추가 아이콘
          Icons.delete, // 정산 유형 삭제 아이콘
          Icons.tire_repair, // 정산 유형 수정 아이콘
        ],
      ),
    );
  }
}