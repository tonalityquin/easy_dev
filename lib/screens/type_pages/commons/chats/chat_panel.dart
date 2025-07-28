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
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<DocumentSnapshot>? _chatSubscription;

  String latestMessage = '';
  Timestamp? latestTimestamp;

  @override
  void initState() {
    super.initState();
    _listenToLatestMessage();
  }

  void _listenToLatestMessage() {
    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.roomId)
        .collection('state')
        .doc('latest_message')
        .snapshots()
        .listen((docSnapshot) {
      final data = docSnapshot.data();
      if (data == null) return;

      setState(() {
        latestMessage = data['message'] ?? '';
        latestTimestamp = data['timestamp'];
      });
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final message = {
      'message': text,
      'timestamp': Timestamp.now(),
    };

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.roomId)
        .collection('state')
        .doc('latest_message')
        .set(message);

    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String timeText = '';
    if (latestTimestamp != null) {
      try {
        timeText = DateFormat('yyyy-MM-dd HH:mm')
            .format(latestTimestamp!.toDate().toLocal());
      } catch (_) {}
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: 100,
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('[익명]', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(latestMessage),
              const SizedBox(height: 8),
              Text(
                timeText.isNotEmpty ? '🕒 $timeText' : '',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
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
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
