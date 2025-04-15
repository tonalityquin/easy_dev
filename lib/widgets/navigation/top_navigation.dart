import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';
import '../dialog/area_picker_dialog.dart';

class TopNavigation extends StatefulWidget implements PreferredSizeWidget {
  final double height;

  const TopNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  State<TopNavigation> createState() => _TopNavigationState();
}

class _TopNavigationState extends State<TopNavigation> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_initialized) {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      areaState.initialize(userState.area).then((_) {
        if (mounted) {
          setState(() {
            _initialized = true;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final plateState = context.read<PlateState>();

    final selectedArea = areaState.currentArea;
    // dev는 모든 지역 선택 가능, 그 외는 동일 division만
    final isAreaSelectable = true;

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
              selectedArea,
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
