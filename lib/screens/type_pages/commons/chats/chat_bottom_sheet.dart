import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/user/user_state.dart';
import 'chat_panel.dart';
import '../../../../utils/snackbar_helper.dart'; // ✅ 경로 확인

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

void chatBottomSheet(BuildContext context) {
  final currentUser = context.read<UserState>().user;
  final String? roomId = currentUser?.currentArea?.trim();

  if (roomId == null || roomId.isEmpty) {
    // 🔄 SnackBar → snackbar_helper
    showSelectedSnackbar(context, '채팅을 위해 currentArea가 설정되어야 합니다.');
    return;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (ctx) {
      final inset = MediaQuery.of(ctx).viewInsets.bottom;
      final maxSheetH = MediaQuery.of(ctx).size.height * 0.6;

      return AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: inset),
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                ),
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
                Flexible(
                  child: ChatPanel(roomId: roomId),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

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
