import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  List<String> _shortcuts = [];

  String get _prefsKey => 'chat_shortcuts_${widget.roomId}';

  @override
  void initState() {
    super.initState();
    _listenToLatestMessage();
    _loadShortcuts();
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _chatSubscription?.cancel();
      _listenToLatestMessage();
      _loadShortcuts();
    }
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

      if (!mounted) return;
      setState(() {
        latestMessage = (data['message'] as String?) ?? '';
        final ts = data['timestamp'];
        latestTimestamp = ts is Timestamp ? ts : null;
      });
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.roomId)
          .collection('state')
          .doc('latest_message')
          .set({
        'message': text,
        'timestamp': FieldValue.serverTimestamp(), // 서버시간 권장
      }, SetOptions(merge: true));

      _controller.clear();
      _focusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전송 실패: $e')),
      );
    }
  }

  Future<void> _loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _shortcuts = prefs.getStringList(_prefsKey) ?? [];
    });
  }

  Future<void> _saveShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _shortcuts);
  }

  Future<void> _addShortcut() async {
    final textCtrl = TextEditingController();
    final added = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('쇼트컷 추가'),
        content: Column(
          children: [
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity, // 폭 확장
              child: CupertinoTextField(
                controller: textCtrl,
                placeholder: '자주 쓰는 문구를 입력하세요',
                autofocus: true,
                padding: const EdgeInsets.all(12),
                minLines: 1,
                maxLines: 3,
                onSubmitted: (_) => Navigator.of(context).pop(textCtrl.text.trim()),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(textCtrl.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    final value = (added ?? '').trim();
    if (value.isEmpty) return;

    if (_shortcuts.contains(value)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 같은 쇼트컷이 있습니다.')),
      );
      return;
    }

    setState(() => _shortcuts.add(value));
    await _saveShortcuts();
  }

  Future<void> _removeShortcut(String value) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('삭제 확인'),
        content: Text('"$value" 쇼트컷을 삭제하시겠어요?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _shortcuts.remove(value));
    await _saveShortcuts();
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
    final ts = latestTimestamp;
    if (ts != null) {
      try {
        final dt = ts.toDate();
        if (dt.millisecondsSinceEpoch > 0) {
          timeText = DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
        }
      } catch (_) {}
    }

    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Stack(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _addShortcut,
                icon: const Icon(Icons.add),
                label: const Text('쇼트컷 추가'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  foregroundColor: Colors.blue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: double.infinity,
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
                if (_shortcuts.isNotEmpty) ...[
                  SizedBox(
                    height: 40,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: _shortcuts.map((s) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onLongPress: () => _removeShortcut(s),
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  _controller.text = s;
                                  _controller.selection = TextSelection.fromPosition(
                                    TextPosition(offset: _controller.text.length),
                                  );
                                  _focusNode.requestFocus();
                                },
                                icon: const Icon(Icons.bolt, size: 16),
                                label: Text(s, overflow: TextOverflow.ellipsis),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  minimumSize: const Size(0, 36),
                                  side: const BorderSide(color: Colors.grey),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
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
              decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sendMessage,
                tooltip: '보내기',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
