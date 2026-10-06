import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';

class SensorPlateSuccessSnackbar {
  SensorPlateSuccessSnackbar._();

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context, {
    required String plate,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: const Duration(milliseconds: 2400),
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        padding: EdgeInsets.zero,
        content: _SensorPlateSuccessCard(
          plate: plate,
          reduceMotion: reduceMotion,
        ),
      ),
    );
  }
}

class _SensorPlateSuccessCard extends StatelessWidget {
  const _SensorPlateSuccessCard({
    required this.plate,
    required this.reduceMotion,
  });

  final String plate;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final child = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: tokens.successContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: tokens.success.withOpacity(tokens.isDark ? 0.7 : 0.48),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.scrim.withOpacity(tokens.isDark ? 0.34 : 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tokens.success,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              color: tokens.onSuccess,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '차량 번호 인식 완료',
                  style: text.labelLarge?.copyWith(
                    color: tokens.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  plate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (reduceMotion) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, value, animatedChild) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: Transform.scale(
              scale: 0.94 + (0.06 * value),
              child: animatedChild,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
