import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../screens/secondary_pages/office_mode_pages/user_management_pages/sections/role_type.dart';
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
      RoleType.admin,
      RoleType.ceo,
      RoleType.highManager,
      RoleType.middleManager,
      RoleType.lowManager,
    ].contains(userRole);

    final selectedModeLabel = userRole == RoleType.lowField ? '보조 페이지' : manageState.currentStatus.label;

    return AppBar(
      backgroundColor: Colors.white,
      centerTitle: true,
      title: GestureDetector(
        onTap: isSelectable
            ? () => secondaryPickerBottomSheet(
                  context: context,
                  manageState: manageState,
                  currentStatus: selectedModeLabel,
                  availableStatus: getFilteredAvailableStatus(
                    userRole,
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

  List<String> getFilteredAvailableStatus(RoleType role) {
    if (role == RoleType.dev) {
      // dev는 모든 페이지 접근 가능
      return ModeStatus.values.map((e) => e.label).toList();
    }

    if ([
      RoleType.admin,
      RoleType.ceo,
      RoleType.highManager,
      RoleType.middleManager,
      RoleType.lowManager,
    ].contains(role)) {
      return ModeStatus.values
          .where((mode) => mode != ModeStatus.dev && mode != ModeStatus.document)
          .map((e) => e.label)
          .toList();
    }

    // 그 외 필드 계열(lowField, middleField, highField 등)은 보조 페이지만 가능
    return [ModeStatus.field.label];
  }
}
