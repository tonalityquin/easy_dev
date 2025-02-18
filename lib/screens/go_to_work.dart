import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider 사용
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바
import '../../../states/user_state.dart'; // 사용자 상태 가져오기

class GoToWork extends StatelessWidget {
  const GoToWork({super.key});

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
          final isWorking = userState.isWorking; // 출근 상태 가져오기

          // ✅ 출근 상태일 경우 즉시 TypePage로 이동
          if (isWorking) {
            Future.microtask(() {
              Navigator.pushReplacementNamed(context, '/type_page');
            });
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '사용자 정보',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text('이름: $name'),
                Text('전화번호: $phone'),
                Text('역할: $role'),
                Text('지역: $area'),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    userState.toggleWorkStatus(); // 출근/퇴근 토글
                    if (userState.isWorking) {
                      Navigator.pushReplacementNamed(context, '/type_page'); // 출근 시 TypePage로 이동
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isWorking ? Colors.grey : Colors.white, // 출근 상태에 따라 색상 변경
                  ),
                  child: Text(isWorking ? '퇴근' : '출근'),
                ),
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
