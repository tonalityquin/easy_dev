import 'package:flutter/material.dart';

class AreaChatIconButton extends StatelessWidget {
  const AreaChatIconButton({
    super.key,
    required this.areaName,
    required this.onPressed,
    this.unreadCount = 0,
    this.width = 42,
    this.height = 34,
  });

  final String areaName;
  final VoidCallback? onPressed;
  final int unreadCount;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final area = areaName.trim();
    final enabled = area.isNotEmpty && onPressed != null;
    final active = unreadCount > 0;
    final color = active ? cs.error : cs.primary;

    return Tooltip(
      message: enabled ? '$area 채팅 열기' : '지역 정보 없음',
      child: Material(
        color: Color.alphaBlend(color.withOpacity(active ? .14 : .10), cs.surface),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: width,
                  height: height,
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
                        unreadCount > 99 ? '99+' : '$unreadCount',
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
  }
}
