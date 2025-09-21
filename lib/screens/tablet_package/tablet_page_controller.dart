// lib/screens/tablet_package/tablet_page_controller.dart
import 'package:flutter/material.dart';

import '../../utils/logout_helper.dart';

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

  Future<void> _logout(BuildContext context) async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: true,
      delay: const Duration(seconds: 1),
      // 목적지 미지정 → 기본(허브 선택)으로 이동
    );
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
