import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/google_drive_chat_helper.dart';

void showChatBottomSheet(BuildContext context) {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _fileIdInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  String? fileId;
  List<String> fileIdHistory = [];
  Future<List<Map<String, dynamic>>>? chatFuture;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _focusNode.requestFocus();
        final prefs = await SharedPreferences.getInstance();
        final savedId = prefs.getString('chat_file_id');
        final history = prefs.getStringList('chat_file_id_history') ?? [];

        if (savedId != null && savedId.isNotEmpty) {
          fileId = savedId;
          chatFuture = GoogleDriveChatHelper.readChatJsonFile(fileId!);
        }

        fileIdHistory = history.toSet().toList(); // 중복 제거
      });

      return StatefulBuilder(
        builder: (ctx, setState) {
          void scrollToBottom() {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent + 150,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            });
          }

          Future<void> saveFileId(String id) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('chat_file_id', id);
            final updatedHistory = [id, ...fileIdHistory.where((e) => e != id)].take(5).toList();
            await prefs.setStringList('chat_file_id_history', updatedHistory);
            setState(() {
              fileId = id;
              fileIdHistory = updatedHistory;
              chatFuture = GoogleDriveChatHelper.readChatJsonFile(fileId!);
            });
          }

          Future<void> clearFileId() async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('chat_file_id');
            setState(() {
              fileId = null;
              chatFuture = null;
            });
          }

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
                // 타이틀 + 링크 버튼
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
                      tooltip: '구글 드라이브 ID 설정',
                      onPressed: () {
                        showDialog(
                          context: ctx,
                          builder: (_) => AlertDialog(
                            title: const Text('Google Drive JSON ID 연결'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: _fileIdInputController,
                                  decoration: const InputDecoration(hintText: '예: 1RlsEmXG...'),
                                ),
                                const SizedBox(height: 12),
                                if (fileIdHistory.isNotEmpty)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('최근 사용한 ID'),
                                      ...fileIdHistory.map((id) => ListTile(
                                        dense: true,
                                        title: Text(id),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          saveFileId(id);
                                        },
                                      )),
                                    ],
                                  ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  clearFileId();
                                  _fileIdInputController.clear();
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
                                  final newId = _fileIdInputController.text.trim();
                                  if (newId.isNotEmpty) {
                                    saveFileId(newId);
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

                if (fileId == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('채팅창을 연결하세요.', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  )
                else
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: chatFuture,
                    builder: (ctx, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final messages = snapshot.data!;
                      scrollToBottom();

                      final Map<String, List<Map<String, dynamic>>> groupedMessages = {};
                      for (var msg in messages) {
                        final rawTime = msg['timestamp'] ?? '';
                        String date = 'Unknown';
                        try {
                          date = DateFormat('yyyy-MM-dd').format(DateTime.parse(rawTime).toLocal());
                        } catch (_) {}
                        groupedMessages.putIfAbsent(date, () => []).add(msg);
                      }

                      return Column(
                        children: [
                          Container(
                            constraints: BoxConstraints(
                              maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                            ),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListView(
                              controller: _scrollController,
                              shrinkWrap: true,
                              children: groupedMessages.entries.expand((entry) {
                                final date = entry.key;
                                final items = entry.value;

                                return [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Center(
                                      child: Text(
                                        date,
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700]),
                                      ),
                                    ),
                                  ),
                                  ...items.map((msg) {
                                    final name = msg['name'] ?? '익명';
                                    final text = msg['message'] ?? '';
                                    final rawTime = msg['timestamp'] ?? '';
                                    String time = '';
                                    try {
                                      time = DateFormat('HH:mm').format(DateTime.parse(rawTime).toLocal());
                                    } catch (_) {}

                                    return Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.grey.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('[$name]', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          Text(text),
                                          const SizedBox(height: 4),
                                          Text('🕒 $time', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                        ],
                                      ),
                                    );
                                  })
                                ];
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  decoration: InputDecoration(
                                    hintText: '메시지를 입력하세요...',
                                    filled: true,
                                    fillColor: Colors.grey[200],
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTapDown: (_) => setState(() {}),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.send, color: Colors.white),
                                    onPressed: () async {
                                      final text = _controller.text.trim();
                                      if (text.isEmpty || fileId == null) return;

                                      const userName = '근무자';
                                      final message = {
                                        'name': userName,
                                        'message': text,
                                        'timestamp': DateTime.now().toUtc().toIso8601String(),
                                      };

                                      await GoogleDriveChatHelper.appendChatMessageJson(fileId!, message);
                                      _controller.clear();

                                      setState(() {
                                        chatFuture = GoogleDriveChatHelper.readChatJsonFile(fileId!);
                                      });

                                      scrollToBottom();

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('메시지가 전송되었습니다')),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 80),
                        ],
                      );
                    },
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}
