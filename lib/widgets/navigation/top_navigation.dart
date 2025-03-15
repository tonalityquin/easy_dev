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
    final plateState = context.read<PlateState>(); // 🔹 watch → read로 변경
    final selectedArea = _getSelectedArea(areaState);
    final UserRole userRole = UserRole.values.firstWhere(
          (role) => role.name == userState.role,
      orElse: () => UserRole.Admin,
    );

    _initializeAreaIfEmpty(areaState, userState);

    return AppBar(
      title: DropdownButton<String>(
        value: selectedArea,
        underline: const SizedBox.shrink(),
        dropdownColor: Colors.white,
        items: _buildDropdownItems(areaState),
        onChanged: (userRole == UserRole.Fielder || userRole == UserRole.FieldLeader)
            ? null
            : (newArea) {
          if (newArea != null) {
            areaState.updateArea(newArea);
            plateState.syncWithAreaState(newArea); // 🔹 PlateState에서 자동으로 print() 실행
          }
        },
        style: const TextStyle(color: Colors.black),
      ),
      centerTitle: true,
      backgroundColor: Colors.blue,
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

  List<DropdownMenuItem<String>> _buildDropdownItems(AreaState areaState) {
    return areaState.availableAreas.map((area) {
      return DropdownMenuItem<String>(
        value: area,
        child: Text(area),
      );
    }).toList();
  }
}

enum UserRole {
  Admin,
  Fielder,
  FieldLeader,
}
