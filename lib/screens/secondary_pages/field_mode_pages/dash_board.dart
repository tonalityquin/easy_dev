import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider 사용
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바
import '../../../states/user_state.dart'; // 사용자 상태 가져오기

class DashBoard extends StatelessWidget {
  const DashBoard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          // 로그인한 사용자 정보 가져오기
          final name = userState.name;
          final phone = userState.phone;
          final role = userState.role;
          final area = userState.area;

          // 본문에 사용자 정보 표시
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '사용자 정보',
                  style: Theme.of(context).textTheme.titleLarge, // 수정된 부분
                ),
                const SizedBox(height: 10),
                Text('이름: $name'),
                Text('전화번호: $phone'),
                Text('역할: $role'),
                Text('지역: $area'),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const SecondaryMiniNavigation(
        // 하단 내비게이션
        icons: [
          Icons.search, // 검색 아이콘
          Icons.person, // 프로필 아이콘
          Icons.sort, // 정렬 아이콘
        ],
      ),
    );
  }
}
