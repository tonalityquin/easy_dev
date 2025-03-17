import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider 사용
import 'dart:io'; // 앱 종료를 위한 패키지 추가
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/show_snackbar.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바
import '../../../states/user/user_state.dart'; // 사용자 상태 가져오기

class DashBoard extends StatelessWidget {
  const DashBoard({super.key});

  /// 🔹 출근 / 퇴근 처리
  Future<void> _handleWorkStatus(UserState userState) async {
    if (userState.isWorking) {
      await userState.isHeWorking(); // Firestore에서 출근 상태 해제 (isWorking = false)

      // 🔹 Firestore 업데이트 확인을 위해 1초 대기
      await Future.delayed(const Duration(seconds: 1));

      exit(0); // 🔹 Firestore 반영 후 앱 종료
    } else {
      userState.isHeWorking(); // 🔹 출근 상태 변경
    }
  }

  /// 🔹 로그아웃 처리
  Future<void> _logout(BuildContext context) async {
    try {
      print("[DEBUG] 로그아웃 시도");

      final userState = Provider.of<UserState>(context, listen: false);

      await userState.isHeWorking(); // 🔹 Firestore에서 isWorking을 false로 설정
      print("[DEBUG] 사용자 업무 상태(isWorking) 업데이트 완료");

      // 🔹 Firestore 업데이트 확인을 위해 1초 대기
      await Future.delayed(const Duration(seconds: 1));

      await userState.clearUserToPhone(); // 🔹 사용자 데이터 삭제
      print("[DEBUG] UserState 데이터 삭제 완료");

      // 🔹 SharedPreferences 초기화 (자동 로그인 방지)
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('phone');
      await prefs.remove('area');
      await prefs.setBool('isLoggedIn', false); // 🔹 자동 로그인 방지를 위해 false 설정
      print("[DEBUG] SharedPreferences 데이터 삭제 완료");

      // 🔹 로그인 페이지로 이동
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      print("[DEBUG] 로그인 페이지로 이동 완료");

    } catch (e) {
      print("[DEBUG] 로그아웃 중 오류 발생: $e");
      showSnackbar(context, '로그아웃 실패: $e');
    }
  }


  /// 🔹 UI 렌더링
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '사용자 정보',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text('이름: ${userState.name}'),
                Text('전화번호: ${userState.phone}'),
                Text('역할: ${userState.role}'),
                Text('지역: ${userState.area}'),
                const SizedBox(height: 20),

                // 🔹 출근 / 퇴근 버튼
                ElevatedButton(
                  onPressed: () => _handleWorkStatus(userState),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: userState.isWorking ? Colors.white : Colors.white,
                  ),
                  child: Text(userState.isWorking ? '퇴근' : '출근'),
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
