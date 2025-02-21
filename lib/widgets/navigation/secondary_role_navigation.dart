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

  @override
  Widget build(BuildContext context) {
    final manageState = context.watch<SecondaryAccessState>(); // 모드 상태
    final userState = context.watch<UserState>(); // 사용자 상태
    final userRole = userState.role.toLowerCase(); // 사용자 역할

    // 🚀 역할 기반 모드 결정 (중복 제거)
    final selectedMode = userRole == 'fielder' ? 'Field Mode' : manageState.currentStatus;

    return AppBar(
      title: RoleBasedDropdown(
        userRole: userRole,
        selectedMode: selectedMode,
        availableStatus: _getFilteredAvailableStatus(userRole, manageState.availableStatus),
        onModeChange: (newMode) {
          if (newMode != null && userRole != 'fielder') {
            manageState.updateManage(newMode); // 새로운 모드 설정
          }
        },
      ),
      centerTitle: true, // 타이틀 중앙 정렬
      backgroundColor: Colors.green, // 배경색
    );
  }

  /// **사용자 역할에 따라 선택 가능한 모드 필터링**
  /// - `fielder`는 `Field Mode` 고정, `Statistics Mode` 선택 불가
  List<String> _getFilteredAvailableStatus(String userRole, List<String> availableStatus) {
    if (userRole == 'fielder') {
      return ['Field Mode']; // 🚀 Fielder는 항상 Field Mode
    }

    // 🚀 dev 직급은 Statistics Mode 사용 가능
    if (userRole == 'dev') {
      return availableStatus;
    }

    // 기본적으로 Statistics Mode는 제외
    return availableStatus.where((mode) => mode != 'Statistics Mode').toList();
  }
}

/// **RoleBasedDropdown**
/// - 역할 및 상태에 따라 드롭다운 구성
class RoleBasedDropdown extends StatelessWidget {
  final String userRole; // 사용자 역할
  final String selectedMode; // 현재 선택된 모드
  final List<String> availableStatus; // 사용 가능한 상태 목록
  final ValueChanged<String?> onModeChange; // 상태 변경 콜백

  const RoleBasedDropdown({
    super.key,
    required this.userRole,
    required this.selectedMode,
    required this.availableStatus,
    required this.onModeChange,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: userRole == 'fielder', // 🚀 Fielder는 드롭다운 비활성화
      child: DropdownButton<String>(
        value: selectedMode,
        underline: Container(),
        // 밑줄 제거
        dropdownColor: Colors.white,
        // 드롭다운 배경색
        items: _buildDropdownItems(),
        onChanged: onModeChange,
      ),
    );
  }

  /// **드롭다운 아이템 빌더**
  List<DropdownMenuItem<String>> _buildDropdownItems() {
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
}
