import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/user/user_state.dart';
import 'chat_panel.dart';

/// 🔸 최신 메시지를 실시간으로 스트리밍하는 함수 (단일 문서)
Stream<String> latestMessageStream(String roomId) {
  return FirebaseFirestore.instance
      .collection('chats')
      .doc(roomId)
      .collection('state')
      .doc('latest_message')
      .snapshots()
      .map((snapshot) {
    final data = snapshot.data();
    if (data != null && data.containsKey('message')) {
      return data['message'] ?? '';
    }
    return '';
  });
}

/// 🔹 채팅 바텀시트
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
            ChatPanel(roomId: roomId),
          ],
        ),
      );
    },
  );
}

/// 🔹 채팅 버튼 위젯 (TypePage 등에서 사용)
class ChatOpenButton extends StatelessWidget {
  const ChatOpenButton({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = context.read<UserState>().user;
    final String? roomId = currentUser?.currentArea?.trim();

    if (roomId == null || roomId.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<String>(
      stream: latestMessageStream(roomId),
      builder: (context, snapshot) {
        final latestMsg = snapshot.data ?? '채팅 열기';

        return ElevatedButton(
          onPressed: () {
            chatBottomSheet(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(
            latestMsg.length > 20 ? '${latestMsg.substring(0, 20)}...' : latestMsg,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
