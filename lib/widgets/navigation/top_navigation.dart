import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/area_state.dart';

/// TopNavigation 위젯
/// - 지역 선택 및 전환 기능 제공
class TopNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height; // AppBar 높이 (기본값: kToolbarHeight)

  const TopNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final selectedArea = areaState.currentArea;

    return AppBar(
      title: DropdownButton<String>(
        value: selectedArea,
        underline: Container(), // 드롭다운 아래 선 제거
        dropdownColor: Colors.white,
        items: areaState.availableAreas.map((area) {
          return DropdownMenuItem<String>(
            value: area,
            child: Text(
              area,
              style: const TextStyle(color: Colors.black),
            ),
          );
        }).toList(),
        onChanged: (newArea) {
          if (newArea != null) {
            areaState.updateArea(newArea); // 지역 상태 업데이트
          }
        },
      ),
      centerTitle: true,
      backgroundColor: Colors.blue,
    );
  }
}
