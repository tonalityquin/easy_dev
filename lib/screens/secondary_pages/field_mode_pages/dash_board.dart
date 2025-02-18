import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider 사용
import 'dart:io'; // 앱 종료를 위한 패키지 추가
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바
import '../../../states/user_state.dart'; // 사용자 상태 가져오기

class DashBoard extends StatelessWidget {
  const DashBoard({super.key});

  /// 🔹 퇴근 버튼: Firestore에서 isWorking = false 설정 후 앱 종료
  Future<void> _handleWorkStatus(UserState userState) async {
    if (userState.isWorking) {
      await userState.toggleWorkStatus(); // Firestore에서 출근 상태 해제 (isWorking = false)

      // 🔹 Firestore 업데이트 확인을 위해 1초 대기
      await Future.delayed(const Duration(seconds: 1));

      exit(0); // 🔹 Firestore 반영 후 앱 종료
    } else {
      userState.toggleWorkStatus(); // 🔹 출근 상태 변경
    }
  }

  /// 🔹 로그아웃: isWorking 값을 유지한 채 사용자 데이터 삭제 후 앱 종료
  Future<void> _logout(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);

      await userState.clearUser(); // 🔹 사용자 데이터 삭제 (isWorking 값은 변경하지 않음)
      exit(0); // 🔹 앱 종료
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그아웃 실패: $e')),
      );
    }
  }

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

                // 🔹 출근 / 퇴근 버튼
                ElevatedButton(
                  onPressed: () => _handleWorkStatus(userState),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isWorking ? Colors.white : Colors.white,
                  ),
                  child: Text(isWorking ? '퇴근' : '출근'),
                ),

                const SizedBox(height: 20),

                // 🔹 로그아웃 버튼
                ElevatedButton(
                  onPressed: () => _logout(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                  ),
                  child: const Text('로그아웃'),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const SecondaryMiniNavigation(
        icons: [
          Icons.search,
          Icons.person,
          Icons.sort,
        ],
      ),
    );
  }
}
