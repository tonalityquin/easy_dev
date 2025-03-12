import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/user_state.dart';

class GoToWork extends StatelessWidget {
  const GoToWork({super.key});

  void _handleWorkStatus(BuildContext context, UserState userState) {
    userState.toggleWorkStatus();
    if (userState.isWorking) {
      Navigator.pushReplacementNamed(context, '/type_page');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          if (userState.isWorking) {
            Future.microtask(() {
              Navigator.pushReplacementNamed(context, '/type_page');
            });
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 120,
                  child: Image.asset('assets/images/belivus_logo.PNG'),
                ),
                const SizedBox(height: 20),
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
