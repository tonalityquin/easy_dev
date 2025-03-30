import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';
import '../dialog/area_picker_dialog.dart';

class TopNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height;

  const TopNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final userState = context.watch<UserState>();
    final plateState = context.read<PlateState>();
    final selectedArea = _getSelectedArea(areaState);

    final UserRole userRole = UserRole.values.firstWhere(
      (role) => role.name == userState.role,
      orElse: () => UserRole.Admin,
    );

    _initializeAreaIfEmpty(areaState, userState);

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: GestureDetector(
        onTap: (userRole == UserRole.Fielder || userRole == UserRole.FieldLeader)
            ? null
            : () => showAreaPickerDialog(
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
            const SizedBox(width: 4),
            const Icon(CupertinoIcons.chevron_down, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  String _getSelectedArea(AreaState areaState) {
    return areaState.availableAreas.contains(areaState.currentArea)
        ? areaState.currentArea
        : areaState.availableAreas.first;
  }

  void _initializeAreaIfEmpty(AreaState areaState, UserState userState) {
    if (areaState.currentArea.isEmpty) {
      areaState.initializeOrSyncArea(userState.area);
    }
  }
}

enum UserRole {
  Admin,
  Fielder,
  FieldLeader,
}
