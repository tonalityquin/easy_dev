import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../states/user/user_state.dart';
import '../../../utils/init/logout_helper.dart';
import '../../../services/endtime_reminder_service.dart';
import 'commute_inside_package/double_commute_in_controller.dart';
import 'commute_inside_package/widgets/double_commute_in_work_button_widget.dart';
import 'commute_inside_package/widgets/double_commute_in_info_card_widget.dart';
import 'commute_inside_package/widgets/double_commute_in_header_widget.dart';

class DoubleCommuteInScreen extends StatefulWidget {
  const DoubleCommuteInScreen({super.key});

  @override
  State<DoubleCommuteInScreen> createState() => _DoubleCommuteInScreenState();
}

class _DoubleCommuteInScreenState extends State<DoubleCommuteInScreen> {
  final controller = DoubleCommuteInController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    controller.initialize(context);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final userState = context.read<UserState>();

      await userState.ensureTodayClockInStatus();
      if (!mounted) return;

      if (userState.isWorking && !userState.hasClockInToday) {
        await _resetStaleWorkingState(userState);
      }
      if (!mounted) return;

      if (userState.isWorking) {
        controller.redirectIfWorking(context, userState);
      }
    });
  }

  Future<void> _resetStaleWorkingState(UserState userState) async {
    await userState.isHeWorking();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isWorking', false);

    await EndTimeReminderService.instance.cancel();
  }

  Future<void> _handleLogout(BuildContext context) async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(milliseconds: 500),
    );
  }

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: cs.onSurfaceVariant.withOpacity(0.80),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return Positioned(
      top: 12,
      left: 12,
      child: IgnorePointer(
        child: Semantics(
          label: 'screen_tag: WorkFlow A commute screen',
          child: Text('WorkFlow A commute screen', style: style),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Consumer<UserState>(
          builder: (context, userState, _) {
            return SafeArea(
              child: Stack(
                children: [
                  _buildScreenTag(context),

                  SingleChildScrollView(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const DoubleCommuteInHeaderWidget(),
                            const DoubleCommuteInInfoCardWidget(),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: DoubleCommuteInWorkButtonWidget(
                                controller: controller,
                                onLoadingChanged: (value) {
                                  setState(() {
                                    _isLoading = value;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: SizedBox(
                                height: 80,
                                child: Image.asset('assets/images/pelican.png'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 16,
                    right: 16,
                    child: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'logout') {
                          _handleLogout(context);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(Icons.logout, color: cs.error),
                              const SizedBox(width: 8),
                              const Text('로그아웃'),
                            ],
                          ),
                        ),
                      ],
                      icon: const Icon(Icons.more_vert),
                    ),
                  ),

                  if (_isLoading || userState.isWorking)
                    Positioned.fill(
                      child: AbsorbPointer(
                        absorbing: true,
                        child: Container(
                          color: cs.scrim.withOpacity(0.35),
                          child: Center(
                            child: CircularProgressIndicator(color: cs.primary),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
