import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/area_state.dart';
import '../../states/plate_state.dart';
import '../../states/user_state.dart';

/// **TopNavigation 위젯**
/// - 지역 선택 및 전환 기능을 제공하는 AppBar
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

    // UserState와 AreaState 동기화
    areaState.syncWithUserState(userState.area);

    // 선택된 지역 값
    final selectedArea = areaState.availableAreas.contains(areaState.currentArea)
        ? areaState.currentArea
        : areaState.availableAreas.first;

    final userRole = userState.role;

    debugPrint('TopNavigation: selectedArea=$selectedArea'); // 디버깅 로그

    return AppBar(
      title: DropdownButton<String>(
        value: selectedArea,
        underline: const SizedBox.shrink(),
        dropdownColor: Colors.white,
        items: areaState.availableAreas.map((area) {
          return DropdownMenuItem<String>(
            value: area,
            child: Text(area),
          );
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
