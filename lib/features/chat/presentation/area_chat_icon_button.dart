import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../application/area_chat_read_receipts.dart';
import '../application/chat_area_key.dart';
import '../data/repositories/firestore_chat_message_repository.dart';
import '../domain/models/chat_message.dart';
import '../domain/repositories/chat_message_repository.dart';

class AreaChatIconButton extends StatefulWidget {
  const AreaChatIconButton({
    super.key,
    required this.areaName,
    required this.onPressed,
    this.width = 42,
    this.height = 34,
  });

  final String areaName;
  final VoidCallback? onPressed;
  final double width;
  final double height;

  @override
  State<AreaChatIconButton> createState() => _AreaChatIconButtonState();
}

class _AreaChatIconButtonState extends State<AreaChatIconButton> {
  final ChatMessageRepository _repository = FirestoreChatMessageRepository();
  StreamSubscription<AreaChatReadReceiptEvent>? _readReceiptSub;
  int _readAtMs = 0;

  @override
  void initState() {
    super.initState();
    _loadReadAt();
    _readReceiptSub = AreaChatReadReceipts.stream.listen((event) {
      if (event.areaKey != normalizeChatAreaKey(widget.areaName)) return;
      if (!mounted) return;
      setState(() {
        _readAtMs = event.readAtMs;
      });
    });
  }

  @override
  void didUpdateWidget(covariant AreaChatIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areaName != widget.areaName) {
      _loadReadAt();
    }
  }

  Future<void> _loadReadAt() async {
    final value = await AreaChatReadReceipts.readAtMs(widget.areaName);
    if (!mounted) return;
    setState(() {
      _readAtMs = value;
    });
  }

  int _unreadCount(List<ChatMessage> messages, String currentUserId) {
    return messages.where((message) {
      if (message.senderId == currentUserId) return false;
      return message.createdAt.millisecondsSinceEpoch > _readAtMs;
    }).length;
  }

  @override
  void dispose() {
    unawaited(_readReceiptSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final area = widget.areaName.trim();
    final enabled = area.isNotEmpty && widget.onPressed != null;
    final currentUserId = context.watch<UserState>().session?.id ?? '';
    final areaKey = normalizeChatAreaKey(area);

    return StreamBuilder<List<ChatMessage>>(
      stream: area.isEmpty ? const Stream<List<ChatMessage>>.empty() : _repository.watchMessages(areaKey, limit: 20),
      builder: (context, snapshot) {
        final unread = _unreadCount(snapshot.data ?? const <ChatMessage>[], currentUserId);
        final active = unread > 0;
        final color = active ? cs.error : cs.primary;

        return Tooltip(
          message: enabled ? '$area 채팅 열기' : '지역 정보 없음',
          child: Material(
            color: Color.alphaBlend(color.withOpacity(active ? .14 : .10), cs.surface),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: enabled ? widget.onPressed : null,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: widget.width,
                height: widget.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: widget.width,
                      height: widget.height,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withOpacity(active ? .52 : .25)),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        active ? Icons.mark_chat_unread_rounded : Icons.chat_bubble_outline_rounded,
                        size: 18,
                        color: enabled ? color : cs.onSurfaceVariant,
                      ),
                    ),
                    if (active)
                      Positioned(
                        right: -4,
                        top: -5,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: cs.error,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: cs.surface, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: TextStyle(
                              color: cs.onError,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
