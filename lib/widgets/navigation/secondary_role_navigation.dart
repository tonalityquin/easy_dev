import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../screens/secondary_pages/office_mode_pages/user_management_pages/user_setting.dart';
import '../../states/secondary/secondary_mode.dart';
import '../../states/user/user_state.dart';
import '../dialog/secondary_picker_bottom_sheet.dart';

class SecondaryRoleNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height;

  const SecondaryRoleNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final manageState = context.watch<SecondaryMode>();
    final userState = context.watch<UserState>();

    final RoleType userRole = RoleType.fromName(userState.role);

    final isSelectable = [
      RoleType.dev,
      RoleType.officer,
      RoleType.fieldLeader,
    ].contains(userRole);

    final selectedModeLabel =
    userRole == RoleType.fielder ? '보조 페이지' : manageState.currentStatus.label;

    return AppBar(
      backgroundColor: Colors.white,
      centerTitle: true,
      title: GestureDetector(
        onTap: isSelectable
            ? () => secondaryPickerBottomSheet(
          context: context,
          manageState: manageState,
          currentStatus: selectedModeLabel,
          availableStatus: _getFilteredAvailableStatus(
            userRole,
            manageState.availableStatus,
          ),
        )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.settings_solid, size: 18, color: Colors.green),
            const SizedBox(width: 6),
            Text(
              selectedModeLabel,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            if (isSelectable) ...[
              const SizedBox(width: 4),
              const Icon(CupertinoIcons.chevron_down, size: 14, color: Colors.grey),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _getFilteredAvailableStatus(RoleType userRole, List<String> availableStatus) {
    if (userRole == RoleType.fielder) return ['보조 페이지'];

    if (userRole == RoleType.fieldLeader) {
      return availableStatus
          .where((mode) => mode != 'Dev Mode' && mode != 'Statistics Mode')
          .toList();
    }

    if (userRole == RoleType.officer) {
      return availableStatus.where((mode) => mode != 'Dev Mode').toList();
    }

    return availableStatus; // dev는 전부 허용
  }
}
