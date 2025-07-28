import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatPanel extends StatefulWidget {
  final String roomId;

  const ChatPanel({super.key, required this.roomId});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> messages = [];
  StreamSubscription<QuerySnapshot>? _chatSubscription;

  @override
  void initState() {
    super.initState();
    _listenToMessages();
  }

  void _listenToMessages() {
    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true) // 최신부터 가져오기
        .limit(3) // 최근 3개 제한
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final newMessages = snapshot.docs
          .map((doc) => doc.data())
          .toList()
          .reversed // 다시 오래된 순으로 정렬
          .toList();

      setState(() {
        messages = List<Map<String, dynamic>>.from(newMessages);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final message = {
      'message': text,
      'timestamp': Timestamp.now(), // ✅ 서버 반영 지연 없는 확정된 타임스탬프
    };

    await FirebaseFirestore.instance.collection('chats').doc(widget.roomId).collection('messages').add(message);

    _controller.clear();
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 150,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupedMessages = <String, List<Map<String, dynamic>>>{};
    for (var msg in messages) {
      final rawTime = msg['timestamp'];
      String date = 'Unknown';
      try {
        date = DateFormat('yyyy-MM-dd').format((rawTime as Timestamp).toDate().toLocal());
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
                ...items.map((msg) {
                  final text = msg['message'] ?? '';
                  final timestamp = msg['timestamp'];
                  String time = '';
                  try {
                    time = DateFormat('HH:mm').format((timestamp as Timestamp).toDate().toLocal());
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
                        const Text('[익명]', style: TextStyle(fontWeight: FontWeight.bold)),
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
