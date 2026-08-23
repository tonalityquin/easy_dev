import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';

class ModifySectorSection extends StatelessWidget {
  const ModifySectorSection({
    super.key,
    required this.sectorName,
    required this.isBusy,
    required this.onPressed,
  });

  final String? sectorName;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final displayName = sectorName?.trim().isNotEmpty == true
        ? sectorName!.trim()
        : '선택되지 않음';
    final selected = sectorName?.trim().isNotEmpty == true;

    return CommonSideDockSection(
      order: 3,
      title: '방문 구역',
      child: Material(
        color: tokens.transparent,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isBusy ? null : onPressed,
          child: AnimatedContainer(
            duration:
                reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? tokens.surfaceSelected : tokens.surfaceOverlay,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(
                color: selected ? tokens.accent : tokens.borderSubtle,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  child: isBusy
                      ? SizedBox(
                          key: const ValueKey<String>('sector_busy'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.accent,
                          ),
                        )
                      : Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.location_city_outlined,
                          key: ValueKey<bool>(selected),
                          color: selected ? tokens.accent : tokens.iconSecondary,
                          size: 21,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .12),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      displayName,
                      key: ValueKey<String>(displayName),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: isBusy ? .5 : 0,
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  child: Icon(
                    isBusy ? Icons.sync_rounded : Icons.chevron_right_rounded,
                    color: tokens.iconSecondary,
                    size: 20,
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
