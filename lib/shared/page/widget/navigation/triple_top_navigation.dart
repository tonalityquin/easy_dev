import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../plate/application/triple/triple_plate_state.dart';
import '../picker_sheet/triple_area_picker_bottom_sheet.dart';

class TripleTopNavigation extends StatelessWidget {
  const TripleTopNavigation({
    super.key,
    this.isAreaSelectable = true,
    this.usePromptUi = false,
  });

  final bool isAreaSelectable;
  final bool usePromptUi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = PromptUiTheme.of(context);
    final areaState = context.watch<AreaState>();
    final plateState = context.read<TriplePlateState>();
    final selectedArea = areaState.currentArea.trim().isNotEmpty
        ? areaState.currentArea.trim()
        : '지역 없음';
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Material(
      color: usePromptUi ? tokens.transparent : Colors.transparent,
      child: InkWell(
        onTap: isAreaSelectable
            ? () => tripleAreaPickerBottomSheet(
                  context: context,
                  areaState: areaState,
                  plateState: plateState,
                  usePromptUi: usePromptUi,
                )
            : null,
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (!isAreaSelectable) return null;
          if (states.contains(WidgetState.pressed)) {
            return cs.primary.withOpacity(0.10);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return cs.primary.withOpacity(0.06);
          }
          return null;
        }),
        child: SizedBox(
          width: double.infinity,
          height: kToolbarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.car, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Flexible(
                child: AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
                  switchInCurve: PromptUiMotion.enter,
                  switchOutCurve: PromptUiMotion.exit,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.16),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    selectedArea,
                    key: ValueKey<String>(selectedArea),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              if (isAreaSelectable) ...[
                const SizedBox(width: 4),
                Icon(
                  CupertinoIcons.chevron_down,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
