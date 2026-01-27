import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/area/area_state.dart';
import '../../states/plate/minor_plate_state.dart';
import '../dialog/minor_area_picker_bottom_sheet.dart';

class MinorTopNavigation extends StatelessWidget {
  final bool isAreaSelectable;

  const MinorTopNavigation({
    super.key,
    this.isAreaSelectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final areaState = context.watch<AreaState>();
    final plateState = context.read<MinorPlateState>();
    final selectedArea = areaState.currentArea;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isAreaSelectable
            ? () => minorAreaPickerBottomSheet(
          context: context,
          areaState: areaState,
          plateState: plateState,
        )
            : null,
        overlayColor: MaterialStateProperty.resolveWith<Color?>(
              (states) {
            if (!isAreaSelectable) return null;
            if (states.contains(MaterialState.pressed)) return cs.primary.withOpacity(0.10);
            if (states.contains(MaterialState.hovered) || states.contains(MaterialState.focused)) {
              return cs.primary.withOpacity(0.06);
            }
            return null;
          },
        ),
        child: SizedBox(
          width: double.infinity,
          height: kToolbarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.car, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                (selectedArea.trim().isNotEmpty) ? selectedArea : '지역 없음',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              if (isAreaSelectable) ...[
                const SizedBox(width: 4),
                Icon(CupertinoIcons.chevron_down, size: 14, color: cs.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
