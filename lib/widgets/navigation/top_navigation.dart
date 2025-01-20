import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/area_state.dart';
import '../../states/plate_state.dart';
import '../../states/user_state.dart';

/// **TopNavigation**
/// - 지역(Area) 선택을 위한 상단 내비게이션
/// - 사용자 역할(Role)에 따라 지역 선택 가능 여부를 제어
/// - `AreaState`와 `PlateState`를 동기화
class TopNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height; // AppBar 높이

  const TopNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>(); // 지역 상태
    final userState = context.watch<UserState>(); // 사용자 상태
    final plateState = context.read<PlateState>(); // 번호판 상태

    // 선택된 지역이 유효하지 않으면 기본값으로 설정
    final selectedArea = areaState.availableAreas.contains(areaState.currentArea)
        ? areaState.currentArea
        : areaState.availableAreas.first;

    final userRole = userState.role; // 사용자 역할

    debugPrint('TopNavigation: selectedArea=$selectedArea'); // 디버깅 로그

    // 지역 상태와 사용자 상태를 동기화
    if (areaState.currentArea.isEmpty) {
      areaState.syncWithUserState(userState.area); // 사용자 상태 기반 지역 동기화
    }

    return AppBar(
      title: DropdownButton<String>(
        value: selectedArea, // 현재 선택된 지역
        underline: const SizedBox.shrink(), // 밑줄 제거
        dropdownColor: Colors.white, // 드롭다운 배경색
        items: areaState.availableAreas.map((area) {
          return DropdownMenuItem<String>(
            value: area,
            child: Text(area), // 지역 이름 표시
          );
        }).toList(),
        onChanged: (userRole == 'Fielder' || userRole == 'Field Leader') // 역할에 따른 제어
            ? null // Fielder와 Field Leader는 지역 선택 불가
            : (newArea) {
          if (newArea != null) {
            areaState.updateArea(newArea); // 지역 업데이트
            plateState.refreshPlateState(); // 번호판 상태 갱신
          }
        },
        style: const TextStyle(color: Colors.black), // 드롭다운 텍스트 스타일
      ),
      centerTitle: true, // 제목 중앙 정렬
      backgroundColor: Colors.blue, // AppBar 배경색
    );
  }
}
