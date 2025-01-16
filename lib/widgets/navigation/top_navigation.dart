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

    final selectedArea = areaState.currentArea;
    final userRole = userState.role;

    return AppBar(
      title: DropdownButton<String>(
        value: selectedArea,
        underline: const SizedBox.shrink(),
        // 드롭다운 아래 선 제거
        dropdownColor: Colors.white,
        // 드롭다운 배경색
        items: areaState.availableAreas.map((area) {
          return DropdownMenuItem<String>(
            value: area,
            child: Text(area),
          );
        }).toList(),
        onChanged: userRole == 'User'
            ? null
            : (newArea) {
                if (newArea != null) {
                  areaState.updateArea(newArea);
                  plateState.refreshPlateState();
                }
              },
        style: const TextStyle(color: Colors.black), // 텍스트 스타일 공통화
      ),
      centerTitle: true,
      backgroundColor: Colors.blue,
    );
  }
}
