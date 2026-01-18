import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easydev/services/endtime_reminder_service.dart';
import 'package:easydev/states/user/user_state.dart';
import 'package:easydev/utils/init/logout_helper.dart';

import 'commute_inside_package/minor_commute_in_controller.dart';
import 'commute_inside_package/widgets/minor_commute_in_work_button_widget.dart';
import 'commute_inside_package/widgets/minor_commute_in_info_card_widget.dart';
import 'commute_inside_package/widgets/minor_commute_in_header_widget.dart';

class MinorCommuteInScreen extends StatefulWidget {
  const MinorCommuteInScreen({super.key});

  @override
  State<MinorCommuteInScreen> createState() => _MinorCommuteInScreenState();
}

class _MinorCommuteInScreenState extends State<MinorCommuteInScreen> {
  final controller = MinorCommuteInController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    controller.initialize(context);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final userState = context.read<UserState>();

      // 1) 오늘 출근 여부 캐시 보장 (Firestore read는 UserState 내부에서 1일 1회)
      await userState.ensureTodayClockInStatus();
      if (!mounted) return;

      // 2) isWorking=true인데 오늘 출근 로그가 없다면 → stale 상태로 보고 자동 리셋
      if (userState.isWorking && !userState.hasClockInToday) {
        await _resetStaleWorkingState(userState);
      }
      if (!mounted) return;

      // 3) 최종 상태 기준으로만 자동 라우팅
      if (userState.isWorking) {
        controller.redirectIfWorking(context, userState);
      }
    });
  }

  Future<void> _resetStaleWorkingState(UserState userState) async {
    await userState.isHeWorking(); // true → false

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
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return Positioned(
      top: 12,
      left: 12,
      child: IgnorePointer(
        child: Semantics(
          label: 'screen_tag: minor commute screen',
          child: Text('minor commute screen', style: style),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                            const MinorCommuteInHeaderWidget(),
                            const MinorCommuteInInfoCardWidget(),
                            const SizedBox(height: 12),

                            SizedBox(
                              width: double.infinity,
                              child: MinorCommuteInWorkButtonWidget(
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
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(Icons.logout, color: Colors.redAccent),
                              SizedBox(width: 8),
                              Text('로그아웃'),
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
                          color: Colors.black.withOpacity(0.2),
                          child: const Center(
                            child: CircularProgressIndicator(),
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
