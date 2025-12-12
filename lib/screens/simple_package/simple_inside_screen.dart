// lib/screens/simple_package/simple_inside_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../states/user/user_state.dart';
import '../../../utils/init/logout_helper.dart';
import '../../services/endTime_reminder_service.dart';
import 'sections/simple_inside_header_widget_section.dart';
import 'sections/widgets/simple_inside_punch_recorder_section.dart';
import 'sections/simple_inside_document_box_button_section.dart';
import 'sections/simple_inside_report_button_section.dart';
import 'simple_inside_controller.dart';

enum SimpleInsideMode {
  leader,
  fieldUser,
}

class SimpleInsideScreen extends StatefulWidget {
  const SimpleInsideScreen({
    super.key,
    this.mode,
  });

  final SimpleInsideMode? mode;

  @override
  State<SimpleInsideScreen> createState() => _SimpleInsideScreenState();
}

class _SimpleInsideScreenState extends State<SimpleInsideScreen> {
  final controller = SimpleInsideController();

  @override
  void initState() {
    super.initState();
    controller.initialize(context);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();

      await userState.ensureTodayClockInStatus();
      if (!mounted) return;

      if (userState.isWorking && !userState.hasClockInToday) {
        await _resetStaleWorkingState(userState);
      }
      if (!mounted) return;
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
          label: 'screen_tag: simple screen',
          child: Text('simple screen', style: style),
        ),
      ),
    );
  }

  SimpleInsideMode _resolveMode(UserState userState) {
    if (widget.mode != null) return widget.mode!;

    String role = '';

    final user = userState.user;
    if (user != null) {
      final rawRole = user.role;
      role = rawRole.trim();
    }

    debugPrint('[SimpleInsideScreen] resolved role="$role"');

    if (role == 'fieldCommon') {
      return SimpleInsideMode.fieldUser;
    }

    return SimpleInsideMode.leader;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Consumer<UserState>(
          builder: (context, userState, _) {
            final mode = _resolveMode(userState);

            final user = userState.user;
            if (user == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final String userId = user.id;
            final String userName = user.name;

            // 🔹 여기서 area = 현재 근무 지역, division = 회사/법인(또는 본사명)으로 사용
            final String area = userState.currentArea;
            final String division = userState.division;

            debugPrint(
              '[SimpleInsideScreen] punchRecorder props → '
                  'userId="$userId", userName="$userName", area="$area", division="$division"',
            );

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
                            const SimpleInsideHeaderWidgetSection(),

                            // 🔹 간편 모드 출퇴근 카드에 회사/지역/유저 정보 전달
                            SimpleInsidePunchRecorderSection(
                              userId: userId,
                              userName: userName,
                              area: area,
                              division: division,
                            ),

                            const SizedBox(height: 6),

                            if (mode == SimpleInsideMode.leader)
                              const _CommonModeButtonGrid()
                            else
                              const _TeamModeButtonGrid(),

                            const SizedBox(height: 1),
                            Center(
                              child: SizedBox(
                                height: 80,
                                child: Image.asset(
                                  'assets/images/pelican.png',
                                ),
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
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CommonModeButtonGrid extends StatelessWidget {
  const _CommonModeButtonGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Row(
          children: [
            Expanded(child: SimpleInsideReportButtonSection()),
            SizedBox(width: 12),
            Expanded(child: SimpleInsideDocumentBoxButtonSection()),
          ],
        ),
      ],
    );
  }
}

class _TeamModeButtonGrid extends StatelessWidget {
  const _TeamModeButtonGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Row(
          children: [
            Expanded(child: SimpleInsideDocumentBoxButtonSection()),
          ],
        ),
      ],
    );
  }
}
