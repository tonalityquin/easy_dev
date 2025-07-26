import 'package:flutter/material.dart';
import '../utils/google_drive_chat_helper.dart';

void showChatBottomSheet(BuildContext context) {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  const String fileId = '1RlsEmXGlf7sK57B-ITEewiFBLg8GOeLD';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: GoogleDriveChatHelper.readChatJsonFile(fileId),
            builder: (ctx, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final messages = snapshot.data!;

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                }
              });

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
                    const Text('구역 채팅', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      height: 200,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView(
                        controller: _scrollController,
                        children: messages.map((msg) {
                          final name = msg['name'] ?? '익명';
                          final text = msg['message'] ?? '';
                          final timestamp = msg['timestamp'] ?? '';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '[$name] $text\n🕒 $timestamp',
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: const InputDecoration(
                              hintText: '메시지를 입력하세요...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: () async {
                            final text = _controller.text.trim();
                            if (text.isEmpty) return;

                            const userName = '근무자';

                            final message = {
                              'name': userName,
                              'message': text,
                              'timestamp': DateTime.now().toUtc().toIso8601String(),
                            };

                            await GoogleDriveChatHelper.appendChatMessageJson(fileId, message);
                            _controller.clear();

                            setState(() {});

                            Future.delayed(const Duration(milliseconds: 100), () {
                              if (_scrollController.hasClients) {
                                _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                              }
                            });

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('메시지가 전송되었습니다')),
                            );
                          },
                        )
                      ],
                    ),

// ✅ 여기에 여백 추가
                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}
