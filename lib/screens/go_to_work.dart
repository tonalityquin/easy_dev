import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider 사용
import '../../../states/user_state.dart'; // 사용자 상태 가져오기

class GoToWork extends StatelessWidget {
  const GoToWork({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                // ✅ 중앙 정렬된 로고 이미지 추가
                SizedBox(
                  height: 120, // 이미지 크기 조절
                  child: Image.asset('assets/images/belivus_logo.PNG'),
                ),
                const SizedBox(height: 20), // 간격 추가

                // 사용자 정보
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

                // 출근/퇴근 버튼
                ElevatedButton(
                  onPressed: () {
                    userState.toggleWorkStatus(); // 출근/퇴근 토글
                    if (userState.isWorking) {
                      Navigator.pushReplacementNamed(context, '/type_page'); // 출근 시 TypePage로 이동
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isWorking ? Colors.white : Colors.white, // 출근 상태에 따라 색상 변경
                  ),
                  child: Text(isWorking ? '퇴근' : '출근'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
