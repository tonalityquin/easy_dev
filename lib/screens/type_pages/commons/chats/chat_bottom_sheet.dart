import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/user/user_state.dart';
import 'chat_panel.dart';

void chatBottomSheet(BuildContext context) {
  final currentUser = context.read<UserState>().user;
  final String? roomId = currentUser?.currentArea?.trim();

  if (roomId == null || roomId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⚠️ 채팅을 위해 currentArea가 설정되어야 합니다.')),
    );
    return;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '구역 채팅',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),

            /// ✅ 로그인한 유저의 currentArea를 기반으로 채팅방 자동 연결
            ChatPanel(roomId: roomId),
          ],
        ),
      );
    },
  );
}
