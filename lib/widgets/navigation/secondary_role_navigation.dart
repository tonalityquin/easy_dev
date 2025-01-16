import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/secondary_role_state.dart';
import '../../states/user_state.dart';

class SecondaryRoleNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height;

  const SecondaryRoleNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  /// **역할 기반 모드 선택 결정**
  String _determineMode(String userRole, String currentStatus) {
    return userRole == 'user' ? 'Field Mode' : currentStatus;
  }

  /// **드롭다운 아이템 빌더**
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
    final manageState = context.watch<SecondaryRoleState>();
    final userState = context.watch<UserState>();

    final userRole = userState.role.toLowerCase();
    final selectedMode = _determineMode(userRole, manageState.currentStatus);

    if (userRole == 'user' && manageState.currentStatus != 'Field Mode') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        manageState.updateManage('Field Mode');
      });
    }

    return AppBar(
      title: IgnorePointer(
        ignoring: userRole == 'user',
        child: DropdownButton<String>(
          value: selectedMode,
          underline: Container(),
          dropdownColor: Colors.white,
          items: _buildDropdownItems(manageState.availableStatus, userRole),
          onChanged: userRole == 'user'
              ? null
              : (newManage) {
                  if (newManage != null) {
                    manageState.updateManage(newManage);
                  }
                },
        ),
      ),
      centerTitle: true,
      backgroundColor: Colors.green,
    );
  }
}
