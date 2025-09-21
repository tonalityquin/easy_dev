// lib/screens/selector_hubs_package/update_alert_bar.dart
import 'package:flutter/material.dart';

class UpdateAlertBar extends StatelessWidget {
  const UpdateAlertBar({
    super.key,
    required this.onTap,
    this.background,
    this.foreground,
  });

  final VoidCallback onTap;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = background ?? cs.primary;
    final fg = foreground ?? cs.onPrimary;

    return Semantics(
      button: true,
      label: '업데이트 보기',
      hint: '최신 업데이트 내용을 확인합니다',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.new_releases_rounded, color: fg),
                const SizedBox(width: 10),
                Expanded(child: Text('업데이트 보기',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: fg, fontWeight: FontWeight.w700))),
                Icon(Icons.keyboard_arrow_up_rounded, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
