import 'package:flutter/material.dart';

class VoiceChatPanel extends StatefulWidget {
  const VoiceChatPanel({super.key});

  @override
  State<VoiceChatPanel> createState() => _VoiceChatPanelState();
}

class _VoiceChatPanelState extends State<VoiceChatPanel> {
  final List<_VoiceChatMessage> _messages = <_VoiceChatMessage>[];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

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
      _messages.add(
        _VoiceChatMessage(
          text: text,
          isMe: true,
          time: DateTime.now(),
        ),
      );
    });

    _controller.clear();
    _scrollToBottomSoon();

    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _VoiceChatMessage(
            text: 'Echo: $text',
            isMe: false,
            time: DateTime.now(),
          ),
        );
      });
      _scrollToBottomSoon();
    });
  }

  void _clearAll() {
    if (_messages.isEmpty) return;
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
    final text = Theme.of(context).textTheme;

    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant.withOpacity(.7)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.chat_bubble_outline_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '무전기 채팅',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (text.titleMedium ?? text.bodyLarge ?? const TextStyle())
                          .copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: '전체 삭제',
                    onPressed: _messages.isEmpty ? null : _clearAll,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: cs.surface,
                child: _messages.isEmpty
                    ? Center(
                        child: Text(
                          '메시지를 보내 보세요.',
                          style: (text.bodyLarge ?? const TextStyle()).copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[_messages.length - 1 - index];
                          return _VoiceChatBubble(message: msg);
                        },
                      ),
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withOpacity(.7)),
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

class _VoiceChatMessage {
  final String text;
  final bool isMe;
  final DateTime time;

  const _VoiceChatMessage({
    required this.text,
    required this.isMe,
    required this.time,
  });
}

class _VoiceChatBubble extends StatelessWidget {
  final _VoiceChatMessage message;

  const _VoiceChatBubble({required this.message});

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.text,
                    style: (text.bodyMedium ?? const TextStyle()).copyWith(color: fg),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.time),
                    style: (text.labelSmall ?? const TextStyle()).copyWith(
                      color: fg.withOpacity(.72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
