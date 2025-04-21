import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../dialog/area_picker_dialog.dart';

class TopNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height;

  const TopNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final plateState = context.read<PlateState>();

    final selectedArea = areaState.currentArea;
    final isAreaSelectable = true; // dev만 체크하려면 userState도 참조 가능

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: GestureDetector(
        onTap: () => showAreaPickerDialog(
          context: context,
          areaState: areaState,
          plateState: plateState,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.car, size: 18, color: Colors.blueAccent),
            const SizedBox(width: 6),
            Text(
              selectedArea.isNotEmpty ? selectedArea : '지역 없음',
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
    );
  }
}
