import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_panel.dart'; // Firestore 기반 ChatPanel 위젯

void chatBottomSheet(BuildContext context) {
  final TextEditingController _roomIdInputController = TextEditingController();

  String? roomId;
  List<String> roomIdHistory = [];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> loadPrefs() async {
            final prefs = await SharedPreferences.getInstance();
            final savedId = prefs.getString('chat_room_id');
            final history = prefs.getStringList('chat_room_id_history') ?? [];

            roomId = (savedId != null && savedId.isNotEmpty)
                ? savedId
                : 'main-room'; // 기본 채팅방

            roomIdHistory = history.toSet().toList();
            setState(() {});
          }

          Future<void> saveRoomId(String id) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('chat_room_id', id);
            final updatedHistory = [id, ...roomIdHistory.where((e) => e != id)].take(5).toList();
            await prefs.setStringList('chat_room_id_history', updatedHistory);
            roomId = id;
            roomIdHistory = updatedHistory;
            setState(() {});
          }

          Future<void> clearRoomId() async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('chat_room_id');
            roomId = null;
            setState(() {});
          }

          // 최초 호출 시 SharedPreferences 로딩
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (roomId == null) loadPrefs();
          });

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 타이틀 및 방 ID 설정 버튼
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 48),
                      const Expanded(
                        child: Center(
                          child: Text(
                            '구역 채팅',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.link),
                        tooltip: '채팅방 ID 설정',
                        onPressed: () {
                          showDialog(
                            context: ctx,
                            builder: (_) => AlertDialog(
                              title: const Text('Firestore 채팅방 ID 연결'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: _roomIdInputController,
                                    decoration: const InputDecoration(hintText: '예: main-room'),
                                  ),
                                  const SizedBox(height: 12),
                                  if (roomIdHistory.isNotEmpty)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('최근 사용한 ID'),
                                        ...roomIdHistory.map((id) => ListTile(
                                          dense: true,
                                          title: Text(id),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            saveRoomId(id);
                                          },
                                        )),
                                      ],
                                    ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    clearRoomId();
                                    _roomIdInputController.clear();
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('초기화'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('취소'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    final newId = _roomIdInputController.text.trim();
                                    if (newId.isNotEmpty) {
                                      saveRoomId(newId);
                                    }
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('적용'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 채팅 영역
                  if (roomId == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '채팅창을 연결하세요.',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  else
                    ChatPanel(roomId: roomId!), // ✅ Firestore 기반 ChatPanel
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
