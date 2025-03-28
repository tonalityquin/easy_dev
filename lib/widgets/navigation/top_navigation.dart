import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';

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
            : () => _showPickerDialog(context, areaState, plateState),
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

  void _showPickerDialog(BuildContext context, AreaState areaState, PlateState plateState) {
    final areas = areaState.availableAreas;
    String tempSelected = areaState.currentArea;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: EdgeInsets.zero, // ✅ 여백 제거
          backgroundColor: Colors.white,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: const Text('', style: TextStyle(color: Colors.black)),
              centerTitle: true,
              iconTheme: const IconThemeData(color: Colors.black),
            ),
            body: Column(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: areas.indexOf(areaState.currentArea),
                    ),
                    itemExtent: 50,
                    onSelectedItemChanged: (index) {
                      tempSelected = areas[index];
                    },
                    children: areas
                        .map((area) => Center(
                      child: Text(
                        area,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ))
                        .toList(),
                  ),
                ),
                const Divider(height: 0),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        areaState.updateArea(tempSelected);
                        plateState.syncWithAreaState();
                      },
                      child: const Text('확인', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
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
