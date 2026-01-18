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
    final areaState = context.watch<AreaState>();
    final plateState = context.read<MinorPlateState>();
    final selectedArea = areaState.currentArea;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isAreaSelectable
            ? () => tripleAreaPickerBottomSheet(
          context: context,
          areaState: areaState,
          plateState: plateState,
        )
            : null,
        splashColor: Colors.grey.withOpacity(0.2),
        highlightColor: Colors.grey.withOpacity(0.1),
        child: SizedBox(
          width: double.infinity,
          height: kToolbarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.car, size: 18, color: Colors.blueAccent),
              const SizedBox(width: 6),
              Text(
                (selectedArea.trim().isNotEmpty) ? selectedArea : '지역 없음',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (isAreaSelectable) ...[
                const SizedBox(width: 4),
                const Icon(CupertinoIcons.chevron_down, size: 14, color: Colors.grey),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
