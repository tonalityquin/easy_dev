import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/game/game_quick_actions.dart';
import '../../../widgets/game/tetris.dart';

class GameArcadeBottomSheet extends StatelessWidget {
  final BuildContext rootContext;

  const GameArcadeBottomSheet({super.key, required this.rootContext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.55,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: cs.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, -4))],
          ),
          child: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.16), borderRadius: BorderRadius.circular(999)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: cs.secondaryContainer,
                        child: Icon(Icons.extension_rounded, color: cs.onSecondaryContainer, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('테트리스', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
                            Text('게임은 닫으면 일시정지되고 다시 열면 이어집니다.', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: GameQuickActions.enabled,
                        builder: (context, on, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(on ? 'Bubble ON' : 'Bubble OFF', style: text.labelMedium?.copyWith(color: on ? cs.primary : cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
                              Switch.adaptive(
                                value: on,
                                onChanged: (v) async {
                                  GameQuickActions.setEnabled(v);
                                  if (v) await GameQuickActions.mountIfNeeded();
                                  HapticFeedback.selectionClick();
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      IconButton(
                        tooltip: '닫기',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Expanded(
                  child: Tetris.embedded(onClose: () => Navigator.of(context).pop()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
