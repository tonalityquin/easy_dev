import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/secondary_access_state.dart';
import '../../states/user_state.dart';

/// **SecondaryRoleNavigation**
/// - 역할 기반으로 드롭다운을 통해 현재 모드를 설정할 수 있는 네비게이션 바
/// - 특정 역할에 따라 모드 선택 제한 가능
class SecondaryRoleNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height; // AppBar 높이

  const SecondaryRoleNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  /// **역할 기반 모드 선택 결정**
  /// - 'Fielder' 역할은 항상 'Field Mode'로 고정
  String _determineMode(String userRole, String currentStatus) {
    if (userRole == 'fielder') {
      return 'Field Mode'; // Fielder는 고정된 모드
    }
    return currentStatus; // 다른 역할은 현재 상태 유지
  }

  /// **드롭다운 아이템 빌더**
  /// - 사용 가능한 상태를 기반으로 드롭다운 메뉴 생성
  List<DropdownMenuItem<String>> _buildDropdownItems(List<String> availableStatus, String userRole) {
    return availableStatus.map((mode) {
      return DropdownMenuItem<String>(
        value: mode,
        child: Text(
          mode,
          style: const TextStyle(color: Colors.black),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final manageState = context.watch<SecondaryAccessState>(); // 모드 상태
    final userState = context.watch<UserState>(); // 사용자 상태

    final userRole = userState.role.toLowerCase(); // 사용자 역할
    final selectedMode = _determineMode(userRole, manageState.currentStatus); // 선택된 모드

    // **역할별 강제 모드 설정**
    if (userRole == 'fielder' && manageState.currentStatus != 'Field Mode') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        manageState.updateManage('Field Mode'); // Fielder는 강제로 Field Mode로 설정
      });
    }

    return AppBar(
      title: IgnorePointer(
        // Fielder만 드롭다운 비활성화
        ignoring: userRole == 'fielder',
        child: DropdownButton<String>(
          value: selectedMode,
          underline: Container(), // 밑줄 제거
          dropdownColor: Colors.white, // 드롭다운 배경색
          items: _buildDropdownItems(manageState.availableStatus, userRole), // 드롭다운 아이템 생성
          onChanged: (newManage) {
            // Fielder는 상태 변경 불가
            if (newManage != null && userRole != 'fielder') {
              manageState.updateManage(newManage); // 새로운 모드 설정
            }
          },
        ),
      ),
      centerTitle: true, // 타이틀 중앙 정렬
      backgroundColor: Colors.green, // 배경색
    );
  }
}
