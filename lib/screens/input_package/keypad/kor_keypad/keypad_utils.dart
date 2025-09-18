import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 서브 레이아웃(행렬 키들) 빌더 유틸
/// - 고유 키 ID(라벨 + r:c)로 애니메이션/pressed 상태 충돌 방지
/// - 각 행을 Expanded로 감싸 4행 균등 분배(부모가 SizedBox.expand로 높이를 강제)
class KorKeypadUtils {
  static Widget buildSubLayout(
      List<List<String>> keyRows,
      void Function(String) onKeyTap, {
        required State state,
        Map<String, AnimationController>? controllers,
        Map<String, bool>? isPressed,
      }) {
    controllers ??= <String, AnimationController>{};
    isPressed ??= <String, bool>{};

    return Column(
      children: List.generate(keyRows.length, (r) {
        final row = keyRows[r];
        return Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(row.length, (c) {
              final label = row[c];
              return _buildAnimatedKeyButton(
                label,
                label.isNotEmpty ? () => onKeyTap(label) : null,
                state,
                controllers!,
                isPressed!,
                r,
                c,
              );
            }),
          ),
        );
      }),
    );
  }

  static Widget _buildAnimatedKeyButton(
      String key,
      VoidCallback? onTap,
      State state,
      Map<String, AnimationController> controllers,
      Map<String, bool> isPressed,
      int rowIndex,
      int colIndex,
      ) {
    if (key.isEmpty) {
      return const Expanded(child: SizedBox());
    }

    final id = '$key#$rowIndex:$colIndex';

    controllers.putIfAbsent(
      id,
          () => AnimationController(
        duration: const Duration(milliseconds: 80),
        vsync: state as TickerProvider,
        lowerBound: 0.0,
        upperBound: 0.1,
      ),
    );
    isPressed.putIfAbsent(id, () => false);

    final controller = controllers[id]!;
    final animation = Tween(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: GestureDetector(
          onTapDown: (_) {
            HapticFeedback.selectionClick();
            state.setState(() => isPressed[id] = true);
            controller.forward();
          },
          onTapUp: (_) {
            state.setState(() => isPressed[id] = false);
            Future.delayed(const Duration(milliseconds: 100), () {
              if (state.mounted) controller.reverse();
            });
            onTap?.call();
          },
          onTapCancel: () {
            state.setState(() => isPressed[id] = false);
            controller.reverse();
          },
          child: Semantics(
            button: true,
            label: _semanticLabel(key),
            child: ScaleTransition(
              scale: animation,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                decoration: BoxDecoration(
                  color: Theme.of(state.context).colorScheme.surfaceVariant.withOpacity(
                    isPressed[id]! ? 0.6 : 0.4,
                  ),
                  borderRadius: BorderRadius.zero,
                  border: Border.all(
                    color: Theme.of(state.context).colorScheme.outlineVariant,
                  ),
                ),
                child: Center(
                  child: Text(
                    key,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _semanticLabel(String key) {
    if (key == 'back') return '뒤로';
    if (key == '공란') return '공란';
    return '키 $key';
  }
}
