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

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "모드 선택",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                const Text(
                  '모드 선택',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: availableStatus.indexOf(currentStatus),
                    ),
                    itemExtent: 50,
                    onSelectedItemChanged: (index) {
                      tempSelected = availableStatus[index];
                    },
                    children: availableStatus
                        .map((mode) => Center(
                      child: Text(
                        mode,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ))
                        .toList(),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40, top: 20),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        manageState.updateManage(tempSelected);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.green, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Text(
                          '확인',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
