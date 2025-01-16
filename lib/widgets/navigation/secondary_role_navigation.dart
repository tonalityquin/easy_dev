import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/secondary_access_state.dart';
import '../../states/user_state.dart';

class SecondaryRoleNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height;

  const SecondaryRoleNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  /// **역할 기반 모드 선택 결정**
  String _determineMode(String userRole, String currentStatus) {
    // 'Fielder'는 Field Mode 고정
    if (userRole == 'fielder') {
      return 'Field Mode';
    }
    return currentStatus; // Field Leader와 다른 역할은 현재 상태 유지
  }

  /// **드롭다운 아이템 빌더**
  List<DropdownMenuItem<String>> _buildDropdownItems(List<String> availableStatus, String userRole) {
    // 'Fielder'는 필터링 없이 모든 상태를 드롭다운에 표시
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
    final manageState = context.watch<SecondaryAccessState>();
    final userState = context.watch<UserState>();

    final userRole = userState.role.toLowerCase(); // 역할 가져오기
    final selectedMode = _determineMode(userRole, manageState.currentStatus);

    // **역할별 강제 모드 설정**
    if (userRole == 'fielder' && manageState.currentStatus != 'Field Mode') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        manageState.updateManage('Field Mode');
      });
    }

    return AppBar(
      title: IgnorePointer(
        // Fielder만 드롭다운 비활성화
        ignoring: userRole == 'fielder',
        child: DropdownButton<String>(
          value: selectedMode,
          underline: Container(),
          dropdownColor: Colors.white,
          items: _buildDropdownItems(manageState.availableStatus, userRole),
          onChanged: (newManage) {
            // 'Fielder'는 상태 변경 불가
            if (newManage != null && userRole != 'fielder') {
              manageState.updateManage(newManage); // 새로운 모드 설정
            }
          },
        ),
      ),
      centerTitle: true,
      backgroundColor: Colors.green,
    );
  }
}
