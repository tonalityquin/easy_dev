import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/secondary/secondary_mode.dart';
import '../../states/user/user_state.dart';

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
            : () => _showPickerDialog(context, manageState, selectedMode, _getFilteredAvailableStatus(userRole, manageState.availableStatus)),
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
    return availableStatus.where((mode) => mode != 'Statistics Mode').toList();
  }

  void _showPickerDialog(
      BuildContext context,
      SecondaryMode manageState,
      String currentStatus,
      List<String> availableStatus,
      ) {
    String tempSelected = currentStatus;

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SizedBox(
            height: 230,
            child: Column(
              children: [
                const Text(
                  '모드 선택',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Divider(),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: availableStatus.indexOf(currentStatus),
                    ),
                    itemExtent: 36,
                    onSelectedItemChanged: (index) {
                      tempSelected = availableStatus[index];
                    },
                    children: availableStatus.map((mode) => Center(child: Text(mode))).toList(),
                  ),
                ),
                const Divider(height: 0),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    manageState.updateManage(tempSelected);
                  },
                  child: const Text('확인', style: TextStyle(color: Colors.green)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
