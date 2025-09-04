import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../routes.dart'; // 라우트 상수(AppRoutes.login)
import '../../states/user/user_state.dart';
import '../../utils/blocking_dialog.dart';
import '../../utils/snackbar_helper.dart';

class TabletPageController extends StatelessWidget {
  const TabletPageController({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 60,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 🔹 로그아웃 버튼 (DashBoardBottomSheet 스타일과 동일)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('로그아웃'),
            style: _logoutBtnStyle(),
            onPressed: () => _logout(context),
          ),
        ),

        const Spacer(),

        const Text(
          '왼쪽 영역(추가 컨텐츠 배치 가능)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 내부 로직: CommonDashBoardController.logout 를 본 파일에 인라인 정의
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _logout(BuildContext context) async {
    try {
      await runWithBlockingDialog(
        context: context,
        message: '로그아웃 중입니다...',
        task: () async {
          final userState = Provider.of<UserState>(context, listen: false);

          // Foreground service 중지
          await FlutterForegroundTask.stopService();

          // 근무 상태 갱신(필요 시)
          await userState.isHeWorking();
          await Future.delayed(const Duration(seconds: 1));

          // 로컬 상태/저장소 초기화
          await userState.clearUserToPhone();

          // (선택) 앱 종료가 필요하면 아래를 사용하세요.
          // SystemNavigator.pop();
        },
      );

      if (!context.mounted) return;

      // 로그인 화면으로 안전하게 라우팅 (기존 스택 제거)
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);

      showSuccessSnackbar(context, '로그아웃 되었습니다.');
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '로그아웃 실패: $e');
      }
    }
  }
}

// 공통 버튼 스타일 (DashBoardBottomSheet 참고)
ButtonStyle _logoutBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
