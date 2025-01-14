import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/secondary_role_state.dart';

/// **ManagementNavigation 위젯**
/// - 지역 선택 및 전환 기능을 제공하는 AppBar
/// - 지역 선택을 위해 DropdownButton을 사용하며, 선택된 지역 상태를 업데이트
class SecondaryRoleNavigation extends StatelessWidget implements PreferredSizeWidget {
  /// **AppBar 높이**
  /// - 기본값: `kToolbarHeight` (표준 툴바 높이)
  final double height;

  /// **SecondaryMiniNavigation 생성자**
  /// - [height]: AppBar의 높이를 설정 (옵션, 기본값: `kToolbarHeight`)
  const SecondaryRoleNavigation({super.key, this.height = kToolbarHeight});

  /// **AppBar 크기 반환**
  /// - `PreferredSizeWidget` 구현을 위해 필요한 메서드
  @override
  Size get preferredSize => Size.fromHeight(height);

  /// **위젯 UI 구성**
  @override
  Widget build(BuildContext context) {
    // **ManagementState 가져오기**
    // - 현재 선택된 지역과 사용 가능한 지역 목록을 관리
    final manageState = context.watch<SecondaryRoleState>();
    final selectMode = manageState.currentStatus; // 현재 선택된 모드

    return AppBar(
      title: DropdownButton<String>(
        value: selectMode,
        // 현재 선택된 지역 값
        underline: Container(),
        // 드롭다운 아래 선 제거
        dropdownColor: Colors.white,
        // 드롭다운 메뉴 배경색
        items: manageState.availableStatus.map((mode) {
          // **지역 목록을 드롭다운 메뉴로 변환**
          return DropdownMenuItem<String>(
            value: mode, // 각 지역의 값
            child: Text(
              mode, // 지역 이름 표시
              style: const TextStyle(color: Colors.black), // 텍스트 스타일
            ),
          );
        }).toList(),
        onChanged: (newManage) {
          // **선택된 지역 변경 처리**
          if (newManage != null) {
            manageState.updateManage(newManage); // 지역 상태 업데이트
          }
        },
      ),
      centerTitle: true, // 제목 가운데 정렬
      backgroundColor: Colors.green, // AppBar 배경색
    );
  }
}
