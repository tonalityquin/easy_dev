import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/secondary/secondary_access_state.dart';
import '../../states/user/user_state.dart';

class SecondaryRoleNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height;

  const SecondaryRoleNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final manageState = context.watch<SecondaryAccessState>();
    final userState = context.watch<UserState>();
    final userRole = userState.role.toLowerCase();
    final selectedMode = userRole == 'fielder' ? 'Field Mode' : manageState.currentStatus;
    return AppBar(
      title: RoleBasedDropdown(
        userRole: userRole,
        selectedMode: selectedMode,
        availableStatus: _getFilteredAvailableStatus(userRole, manageState.availableStatus),
        onModeChange: (newMode) {
          if (newMode != null && userRole != 'fielder') {
            manageState.updateManage(newMode);
          }
        },
      ),
      centerTitle: true,
      backgroundColor: Colors.green,
    );
  }

  List<String> _getFilteredAvailableStatus(String userRole, List<String> availableStatus) {
    if (userRole == 'fielder') {
      return ['Field Mode'];
    }
    if (userRole == 'dev') {
      return availableStatus;
    }
    return availableStatus.where((mode) => mode != 'Statistics Mode').toList();
  }
}

class RoleBasedDropdown extends StatelessWidget {
  final String userRole;
  final String selectedMode;
  final List<String> availableStatus;
  final ValueChanged<String?> onModeChange;

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
      ignoring: userRole == 'fielder',
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
