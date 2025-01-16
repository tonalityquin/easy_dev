import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/area_state.dart';
import '../../states/plate_state.dart';
import '../../states/user_state.dart';

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

    final selectedArea = areaState.availableAreas.contains(areaState.currentArea)
        ? areaState.currentArea
        : areaState.availableAreas.first;

    final userRole = userState.role;

    debugPrint('TopNavigation: selectedArea=$selectedArea'); // 디버깅 로그

    // AreaState와 UserState를 동기화하는 조건 추가
    if (areaState.currentArea.isEmpty) {
      areaState.syncWithUserState(userState.area);
    }

    return AppBar(
      title: DropdownButton<String>(
        value: selectedArea,
        underline: const SizedBox.shrink(),
        dropdownColor: Colors.white,
        items: areaState.availableAreas.map((area) {
          return DropdownMenuItem<String>(value: area, child: Text(area));
        }).toList(),
        onChanged: (userRole == 'Fielder' || userRole == 'Field Leader')
            ? null
            : (newArea) {
                if (newArea != null) {
                  areaState.updateArea(newArea);
                  plateState.refreshPlateState();
                }
              },
        style: const TextStyle(color: Colors.black),
      ),
      centerTitle: true,
      backgroundColor: Colors.blue,
    );
  }
}
