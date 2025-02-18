import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider 사용
import '../../../states/user_state.dart'; // 사용자 상태 가져오기

class GoToWork extends StatelessWidget {
  const GoToWork({super.key});

  /// 🔹 출근/퇴근 버튼 동작
  void _handleWorkStatus(BuildContext context, UserState userState) {
    userState.toggleWorkStatus(); // 출근/퇴근 상태 토글

    if (userState.isWorking) {
      Navigator.pushReplacementNamed(context, '/type_page'); // 출근 시 TypePage로 이동
    }
  }

  /// 🔹 UI 렌더링
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          // ✅ 출근 상태일 경우 즉시 TypePage로 이동
          if (userState.isWorking) {
            Future.microtask(() {
              Navigator.pushReplacementNamed(context, '/type_page');
            });
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🔹 중앙 정렬된 로고 이미지
                SizedBox(
                  height: 120,
                  child: Image.asset('assets/images/belivus_logo.PNG'),
                ),
                const SizedBox(height: 20),

                // 🔹 사용자 정보
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

                // 🔹 출근/퇴근 버튼
                ElevatedButton(
                  onPressed: () => _handleWorkStatus(context, userState),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                  ),
                  child: Text(userState.isWorking ? '퇴근' : '출근'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
