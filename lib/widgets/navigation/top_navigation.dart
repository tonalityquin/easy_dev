import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';
import '../dialog/area_picker_dialog.dart';
import '../../screens/secondary_pages/office_mode_pages/user_management_pages/user_setting.dart'; // ✅ RoleType enum 위치

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

    // 초기화는 한 번만 수행
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
    final userState = context.watch<UserState>();
    final plateState = context.read<PlateState>();

    final RoleType userRole = RoleType.fromName(userState.role);
    final isAreaSelectable = [
      RoleType.dev,
      RoleType.officer,
    ].contains(userRole);

    final selectedArea = areaState.currentArea;

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: GestureDetector(
        onTap: isAreaSelectable
            ? () => showAreaPickerDialog(
          context: context,
          areaState: areaState,
          plateState: plateState,
        )
            : null,
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
