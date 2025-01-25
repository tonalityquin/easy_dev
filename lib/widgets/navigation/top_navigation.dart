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

    // 선택된 지역을 가져오는 로직을 메서드로 추출하여 가독성 개선
    final selectedArea = _getSelectedArea(areaState);

    // 사용자 역할 관리 방식을 enum으로 변경
    final UserRole userRole = UserRole.values.firstWhere(
      (role) => role.name == userState.role,
      orElse: () => UserRole.Admin, // 기본값 설정
    );

    // 지역 초기화 로직 분리
    _initializeAreaIfEmpty(areaState, userState);

    return AppBar(
      title: DropdownButton<String>(
        value: selectedArea,
        // 현재 선택된 지역
        underline: const SizedBox.shrink(),
        // 밑줄 제거
        dropdownColor: Colors.white,
        // 드롭다운 배경색
        items: _buildDropdownItems(areaState),
        // 드롭다운 항목 생성 메서드
        onChanged: (userRole == UserRole.Fielder || userRole == UserRole.FieldLeader)
            ? null
            : (newArea) {
                if (newArea != null) {
                  areaState.updateArea(newArea); // 지역 업데이트
                  plateState.syncWithAreaState(newArea); // 상태 동기화 메서드 호출
                }
              },
        style: const TextStyle(color: Colors.black), // 드롭다운 텍스트 스타일
      ),
      centerTitle: true, // 제목 중앙 정렬
      backgroundColor: Colors.blue, // AppBar 배경색
    );
  }

  /// 선택된 지역을 가져오는 메서드
  String _getSelectedArea(AreaState areaState) {
    return areaState.availableAreas.contains(areaState.currentArea)
        ? areaState.currentArea
        : areaState.availableAreas.first;
  }

  /// 지역 초기화를 위한 메서드
  void _initializeAreaIfEmpty(AreaState areaState, UserState userState) {
    if (areaState.currentArea.isEmpty) {
      areaState.initializeOrSyncArea(userState.area); // 사용자 상태 기반 지역 동기화
    }
  }

  /// 드롭다운 항목 생성 메서드
  List<DropdownMenuItem<String>> _buildDropdownItems(AreaState areaState) {
    return areaState.availableAreas.map((area) {
      return DropdownMenuItem<String>(
        value: area,
        child: Text(area), // 지역 이름 표시
      );
    }).toList();
  }
}

/// 사용자 역할을 관리하기 위한 Enum 추가
enum UserRole {
  Admin,
  Fielder,
  FieldLeader,
}
