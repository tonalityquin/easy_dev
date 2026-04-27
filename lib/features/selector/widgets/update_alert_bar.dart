import 'package:flutter/material.dart';

@immutable
class _UpdateAlertTokens {
  const _UpdateAlertTokens({
    required this.updateBg,
    required this.updateFg,
    required this.inkOverlay,
  });

  final Color updateBg;
  final Color updateFg;
  final Color inkOverlay;

  factory _UpdateAlertTokens.of(
    BuildContext context, {
    Color? updateBg,
    Color? updateFg,
  }) {
    final cs = Theme.of(context).colorScheme;

    return _UpdateAlertTokens(
      updateBg: updateBg ?? cs.primary,
      updateFg: updateFg ?? cs.onPrimary,
      inkOverlay: cs.onSurface.withOpacity(0.06),
    );
  }
}

class UpdateAlertBar extends StatelessWidget {
  const UpdateAlertBar({
    super.key,
    required this.onTapUpdate,
    this.background,
    this.foreground,
  });

  final VoidCallback onTapUpdate;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final t = _UpdateAlertTokens.of(
      context,
      updateBg: background,
      updateFg: foreground,
    );

    return _SingleAlertBar(
      label: '업데이트',
      icon: Icons.new_releases_rounded,
      background: t.updateBg,
      foreground: t.updateFg,
      semanticsLabel: '업데이트',
      semanticsHint: '최신 업데이트 내용을 확인합니다',
      inkOverlay: t.inkOverlay,
      onTap: onTapUpdate,
    );
  }
}

class _SingleAlertBar extends StatelessWidget {
  const _SingleAlertBar({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.semanticsLabel,
    required this.semanticsHint,
    required this.inkOverlay,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final String semanticsLabel;
  final String semanticsHint;
  final Color inkOverlay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: semanticsLabel,
      hint: semanticsHint,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (states) =>
                states.contains(WidgetState.pressed) ? inkOverlay : null,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: foreground,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
