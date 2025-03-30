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

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "지역 선택",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                const Text(
                  '지역 선택',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
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
                        style: const TextStyle(fontSize: 18),
                      ),
                    ))
                        .toList(),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40, top: 20),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        areaState.updateArea(tempSelected);
                        plateState.syncWithAreaState();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.green, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Text(
                          '확인',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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
