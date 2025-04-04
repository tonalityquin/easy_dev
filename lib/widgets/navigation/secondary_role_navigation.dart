import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/secondary/secondary_mode.dart';
import '../../states/user/user_state.dart';
import '../dialog/secondary_picker_dialog.dart';

class SecondaryRoleNavigation extends StatelessWidget implements PreferredSizeWidget {
  final double height;

  const SecondaryRoleNavigation({super.key, this.height = kToolbarHeight});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final manageState = context.watch<SecondaryMode>();
    final userState = context.watch<UserState>();
    final userRole = userState.role.toLowerCase();
    final selectedMode = userRole == 'fielder' ? 'Field Mode' : manageState.currentStatus;

    return AppBar(
      backgroundColor: Colors.white,
      centerTitle: true,
      title: GestureDetector(
        onTap: userRole == 'fielder'
            ? null
            : () => secondaryPickerDialog(
                  context: context,
                  manageState: manageState,
                  currentStatus: selectedMode,
                  availableStatus: _getFilteredAvailableStatus(userRole, manageState.availableStatus),
                ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.settings_solid, size: 18, color: Colors.green),
            const SizedBox(width: 6),
            Text(
              selectedMode,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            if (userRole != 'fielder') ...[
              const SizedBox(width: 4),
              const Icon(CupertinoIcons.chevron_down, size: 14, color: Colors.grey),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _getFilteredAvailableStatus(String userRole, List<String> availableStatus) {
    if (userRole == 'fielder') return ['Field Mode'];
    if (userRole == 'dev') return availableStatus;
    return availableStatus.where((mode) => mode != 'Document Mode').toList();
  }
}
