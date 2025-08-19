import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../screens/secondary_page.dart';
import '../../screens/secondary_pages/office_mode_pages/user_management_pages/sections/role_type.dart';
import '../../states/secondary/secondary_mode.dart';
import '../../states/user/user_state.dart';
import '../../states/secondary/secondary_state.dart'; // ✅ 추가
import '../../widgets/dialog/secondary_picker_bottom_sheet.dart';

class SecondaryRoleNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height;
  final void Function(String selectedLabel)? onModeChanged;

  const SecondaryRoleNavigation({
    super.key,
    this.height = kToolbarHeight,
    this.onModeChanged,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final manageState = context.watch<SecondaryMode>();
    final userState = context.watch<UserState>();

    final RoleType userRole = RoleType.fromName(userState.role);
    final selectedModeLabel = manageState.currentStatus.label;

    final isSelectable = _isRoleSelectable(userRole);

    return AppBar(
      backgroundColor: Colors.white,
      centerTitle: true,
      title: GestureDetector(
        onTap: isSelectable
            ? () => secondaryPickerBottomSheet(
                  context: context,
                  manageState: manageState,
                  currentStatus: selectedModeLabel,
                  availableStatus: getFilteredAvailableStatus(userRole),
                  onConfirm: (newLabel) {
                    final newMode = ModeStatusExtension.fromLabel(newLabel);
                    if (newMode != null) {
                      manageState.changeStatus(newMode);
                      final userState = context.read<UserState>();
                      final pages = SecondaryPage.getUpdatedPages(userState.role, manageState);
                      Provider.of<SecondaryState>(context, listen: false).updatePages(pages);
                    }
                  },
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

  bool _isRoleSelectable(RoleType role) {
    switch (role) {
      case RoleType.lowManager:
      case RoleType.middleManager:
      case RoleType.highManager:
      case RoleType.ceo:
      case RoleType.dev:
        return true;
      default:
        return false;
    }
  }

  List<String> getFilteredAvailableStatus(RoleType role) {
    switch (role) {
      case RoleType.dev:
        return [
          ModeStatus.lowField.label,
          ModeStatus.managerField.label,
          ModeStatus.highManage.label,
          ModeStatus.dev.label,
        ];
      case RoleType.admin:
        return [
          ModeStatus.admin.label,
        ];
      case RoleType.highManager:
      case RoleType.ceo:
        return [
          ModeStatus.managerField.label,
          ModeStatus.highManage.label,
        ];
      case RoleType.middleManager:
      case RoleType.lowManager:
        return [
          ModeStatus.managerField.label,
          ModeStatus.lowMiddleManage.label,
        ];
      default:
        return [];
    }
  }
}
