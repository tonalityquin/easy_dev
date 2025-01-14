import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/area_state.dart';
import '../../states/plate_state.dart';
import '../../states/user_state.dart'; // UserState 가져오기

/// **TopNavigation 위젯**
/// - 지역 선택 및 전환 기능을 제공하는 AppBar
/// - 지역 선택을 위해 DropdownButton을 사용하며, 선택된 지역 상태를 업데이트
class TopNavigation extends StatelessWidget implements PreferredSizeWidget {
  /// **AppBar 높이**
  /// - 기본값: `kToolbarHeight` (표준 툴바 높이)
  final double height;

  /// **TopNavigation 생성자**
  /// - [height]: AppBar의 높이를 설정 (옵션, 기본값: `kToolbarHeight`)
  const TopNavigation({super.key, this.height = kToolbarHeight});

  /// **AppBar 크기 반환**
  /// - `PreferredSizeWidget` 구현을 위해 필요한 메서드
  @override
  Size get preferredSize => Size.fromHeight(height);

  /// **위젯 UI 구성**
  @override
  Widget build(BuildContext context) {
    // **AreaState 및 UserState 가져오기**
    final areaState = context.watch<AreaState>();
    final userState = context.watch<UserState>();
    final plateState = context.read<PlateState>(); // PlateState 접근

    final selectedArea = areaState.currentArea; // 현재 선택된 지역
    final userRole = userState.role; // 현재 사용자 Role

    return AppBar(
      title: DropdownButton<String>(
        value: selectedArea,
        underline: Container(),
        // 드롭다운 아래 선 제거
        dropdownColor: Colors.white,
        // 드롭다운 메뉴 배경색
        items: areaState.availableAreas.map((area) {
          return DropdownMenuItem<String>(
            value: area, // 각 지역의 값
            child: Text(
              area, // 지역 이름 표시
              style: const TextStyle(color: Colors.black), // 텍스트 스타일
            ),
          );
        }).toList(),
        onChanged: userRole == 'User'
            ? null // User는 지역 변경 불가
            : (newArea) {
                if (newArea != null) {
                  areaState.updateArea(newArea); // 지역 상태 업데이트
                  plateState.refreshPlateState(); // PlateState에 변경 알림
                }
              },
      ),
      centerTitle: true, // 제목 가운데 정렬
      backgroundColor: Colors.blue, // AppBar 배경색
    );
  }
}
