import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../application/chat_area_resolver.dart';
import '../controllers/area_chat_controller.dart';
import '../domain/models/chat_message.dart';

class AreaChatPanel extends StatefulWidget {
  const AreaChatPanel({
    super.key,
    this.areaName,
    this.showCloseButton = false,
    this.onClose,
  });

  final String? areaName;
  final bool showCloseButton;
  final VoidCallback? onClose;

  @override
  State<AreaChatPanel> createState() => _AreaChatPanelState();
}

class _AreaChatPanelState extends State<AreaChatPanel> {
  late final AreaChatController _controller;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _boundArea = '';
  String _boundUserId = '';
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AreaChatController();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBindingSoon();
  }

  @override
  void didUpdateWidget(covariant AreaChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areaName != widget.areaName) {
      _boundArea = '';
      _syncBindingSoon();
    }
  }

  String _effectiveAreaForBuild(BuildContext context) {
    final explicit = widget.areaName?.trim() ?? '';
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return ChatAreaResolver.watch(context);
  }

  String _effectiveAreaForRead(BuildContext context) {
    final explicit = widget.areaName?.trim() ?? '';
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return ChatAreaResolver.read(context);
  }

  void _syncBindingSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final area = _effectiveAreaForRead(context);
      final session = context.read<UserState>().session;
      final userId = session?.id ?? '';
      if (session == null || area.isEmpty) {
        if (_boundArea.isNotEmpty || _boundUserId.isNotEmpty) {
          _boundArea = '';
          _boundUserId = '';
          unawaited(_controller.stop());
        }
        return;
      }
      if (_boundArea == area && _boundUserId == userId) {
        return;
      }
      _boundArea = area;
      _boundUserId = userId;
      unawaited(_controller.start(session: session, areaName: area));
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final count = _controller.messages.length;
    if (count != _lastMessageCount) {
      _lastMessageCount = count;
      _scrollToBottomSoon();
    }
    setState(() {});
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _controller.sending) return;
    _textController.clear();
    setState(() {});
    await _controller.sendText(text);
    _scrollToBottomSoon();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final area = _effectiveAreaForBuild(context);
    final userState = context.watch<UserState>();
    final session = userState.session;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final canSend = session != null &&
        area.trim().isNotEmpty &&
        !_controller.sending &&
        _textController.text.trim().isNotEmpty;

    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Container(
              height: 54,
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          area.trim().isEmpty ? '지역 채팅' : '${area.trim()} 채팅',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (text.titleMedium ?? const TextStyle()).copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          '텍스트 채팅',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (text.labelSmall ?? const TextStyle()).copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_controller.loading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: cs.primary,
                      ),
                    ),
                  if (widget.showCloseButton) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: '닫기',
                      onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _buildMessageArea(context, area, session?.id ?? ''),
            ),
            Divider(height: 1, color: cs.outlineVariant.withOpacity(.7)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      enabled: session != null && area.trim().isNotEmpty,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (canSend) {
                          unawaited(_send());
                        }
                      },
                      decoration: InputDecoration(
                        hintText: session == null
                            ? '로그인 정보가 없습니다.'
                            : area.trim().isEmpty
                                ? '지역 정보가 없습니다.'
                                : '메시지 입력…',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canSend ? () => unawaited(_send()) : null,
                    icon: _controller.sending
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: cs.onPrimary,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
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

  Widget _buildMessageArea(
    BuildContext context,
    String area,
    String currentUserId,
  ) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final error = _controller.errorText;

    if (area.trim().isEmpty) {
      return _AreaChatEmptyState(
        icon: Icons.location_off_rounded,
        text: '지역 정보가 없어 채팅을 열 수 없습니다.',
      );
    }

    if (error != null && error.trim().isNotEmpty) {
      return _AreaChatEmptyState(
        icon: Icons.error_outline_rounded,
        text: '채팅을 불러오지 못했습니다.',
      );
    }

    if (_controller.loading && _controller.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.messages.isEmpty) {
      return _AreaChatEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        text: '아직 채팅 메시지가 없습니다.',
      );
    }

    return Container(
      color: cs.surface,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: _controller.messages.length,
        itemBuilder: (context, index) {
          final message = _controller.messages[index];
          return _AreaChatBubble(
            message: message,
            isMe: message.senderId == currentUserId,
            textTheme: text,
          );
        },
      ),
    );
  }
}

class _AreaChatEmptyState extends StatelessWidget {
  const _AreaChatEmptyState({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: (tt.bodyLarge ?? const TextStyle()).copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaChatBubble extends StatelessWidget {
  const _AreaChatBubble({
    required this.message,
    required this.isMe,
    required this.textTheme,
  });

  final ChatMessage message;
  final bool isMe;
  final TextTheme textTheme;

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isMe ? cs.primaryContainer : cs.secondaryContainer;
    final fg = isMe ? cs.onPrimaryContainer : cs.onSecondaryContainer;
    final bubbleAlign = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final crossAxis = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final sender = message.senderName.trim().isEmpty ? '사용자' : message.senderName.trim();
    final identity = message.senderIdentity.trim();

    return Align(
      alignment: bubbleAlign,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: crossAxis,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMe) ...[
                Text(
                  identity.isEmpty ? sender : '$sender · $identity',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (textTheme.labelSmall ?? const TextStyle()).copyWith(
                    color: fg.withOpacity(.78),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                message.text,
                style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _formatTime(message.createdAt),
                style: (textTheme.labelSmall ?? const TextStyle()).copyWith(
                  color: fg.withOpacity(.70),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
