import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';

class PracticeChatLabScreen extends StatefulWidget {
  const PracticeChatLabScreen({super.key});

  @override
  State<PracticeChatLabScreen> createState() => _PracticeChatLabScreenState();
}

class _PracticeChatLabScreenState extends State<PracticeChatLabScreen> {
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _goBackToSelector(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
          (route) => false,
    );
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isMe: true, time: DateTime.now()));
    });

    _controller.clear();
    _scrollToBottomSoon();

    
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: 'Echo: $text', isMe: false, time: DateTime.now()));
      });
      _scrollToBottomSoon();
    });
  }

  void _clearAll() {
    setState(() {
      _messages.clear();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('실험 2: 채팅 기능'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '전체 삭제',
            onPressed: _messages.isEmpty ? null : _clearAll,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          IconButton(
            tooltip: 'Selector로 이동',
            onPressed: () => _goBackToSelector(context),
            icon: const Icon(Icons.home_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: cs.surface,
                child: _messages.isEmpty
                    ? Center(
                  child: Text(
                    '메시지를 보내 보세요.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
                    : ListView.builder(
                  controller: _scrollController,
                  reverse: true, 
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[_messages.length - 1 - index];
                    return _ChatBubble(message: msg);
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '메시지 입력…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('전송'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isMe;
  final DateTime time;

  const _ChatMessage({
    required this.text,
    required this.isMe,
    required this.time,
  });
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = message.isMe ? cs.primaryContainer : cs.secondaryContainer;
    final fg = message.isMe ? cs.onPrimaryContainer : cs.onSecondaryContainer;

    final align = message.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleAlign = message.isMe ? Alignment.centerRight : Alignment.centerLeft;

    return Column(
      crossAxisAlignment: align,
      children: [
        Align(
          alignment: bubbleAlign,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
