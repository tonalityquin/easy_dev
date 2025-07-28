import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'google_drive_chat_helper.dart';

class ChatPanel extends StatefulWidget {
  final String fileId;

  const ChatPanel({super.key, required this.fileId});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> messages = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final result = await GoogleDriveChatHelper.readChatJsonFile(widget.fileId);
    setState(() {
      messages = result;
      isLoading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
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

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    const userName = '근무자';
    final message = {
      'name': userName,
      'message': text,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    await GoogleDriveChatHelper.appendChatMessageJson(widget.fileId, message);

    setState(() {
      messages.add(message);
      _controller.clear();
    });

    _scrollToBottom();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메시지가 전송되었습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    final groupedMessages = <String, List<Map<String, dynamic>>>{};
    for (var msg in messages) {
      final rawTime = msg['timestamp'] ?? '';
      String date = 'Unknown';
      try {
        date = DateFormat('yyyy-MM-dd').format(DateTime.parse(rawTime).toLocal());
      } catch (_) {}
      groupedMessages.putIfAbsent(date, () => []).add(msg);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
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
                }),
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
            Container(
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}
