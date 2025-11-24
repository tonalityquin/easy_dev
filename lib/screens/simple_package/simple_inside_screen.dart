// lib/screens/simple_package/simple_inside_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../states/user/user_state.dart';
import '../../../utils/init/logout_helper.dart';
import '../../services/endtime_reminder_service.dart';
import 'simple_inside_package/simple_inside_controller.dart';
import 'simple_inside_package/sections/simple_inside_report_button_section.dart';
import 'simple_inside_package/sections/simple_inside_work_button_section.dart';
import 'simple_inside_package/sections/simple_inside_user_info_card_section.dart';
import 'simple_inside_package/sections/simple_inside_header_widget_section.dart';

class SimpleInsideScreen extends StatefulWidget {
  const SimpleInsideScreen({super.key});

  @override
  State<SimpleInsideScreen> createState() => _SimpleInsideScreenState();
}

class _SimpleInsideScreenState extends State<SimpleInsideScreen> {
  final controller = SimpleInsideController();

  @override
  void initState() {
    super.initState();
    controller.initialize(context);

    // OPTION A: 자동 라우팅은 최초 진입 시 1회만 수행
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();

      // 1) 오늘 출근 여부 캐시 보장 (Firestore read는 UserState 내부에서 1일 1회)
      await userState.ensureTodayClockInStatus();
      if (!mounted) return;

      // 2) isWorking=true인데 오늘 출근 로그가 없다면
      //    → 어제(또는 그 이전)부터 이어진 잘못된 상태로 간주하고 자동 리셋
      if (userState.isWorking && !userState.hasClockInToday) {
        await _resetStaleWorkingState(userState);
      }
      if (!mounted) return;

      // 3) (기존) 근무 중이면 자동 라우팅 로직은 제거됨
      //    현재는 단순히 상태만 정리하고, 추가 라우팅은 수행하지 않음.
    });
  }

  /// 🔹 "어제 출근만 하고 퇴근 안 누른 상태" 등을 오늘 앱 실행 시 자동으로 정리
  Future<void> _resetStaleWorkingState(UserState userState) async {
    // Firestore user_accounts.isWorking 토글(true → false)
    await userState.isHeWorking();

    // 로컬 SharedPreferences 의 isWorking 도 false 로 맞춤
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isWorking', false);

    // 남아 있을 수 있는 퇴근 알림도 취소
    await EndtimeReminderService.instance.cancel();
  }

  Future<void> _handleLogout(BuildContext context) async {
    // 앱 종료 대신 공통 정책: 허브(Selector)로 이동 + prefs('mode') 초기화
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(milliseconds: 500),
    );
  }

  // ⬇️ 좌측 상단(11시) 고정 라벨: 'simple screen'
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

  @override
  Widget build(BuildContext context) {
    // ✅ 이 화면에서만 뒤로가기로 앱 종료되지 않도록 차단 (스낵바 안내 없음)
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Consumer<UserState>(
          builder: (context, userState, _) {
            // 자동 라우팅은 initState의 addPostFrameCallback에서 1회 수행(현재는 제거됨)

            return SafeArea(
              child: Stack(
                children: [
                  // 11시 라벨
                  _buildScreenTag(context),

                  SingleChildScrollView(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const SimpleInsideHeaderWidgetSection(),
                            const SimpleInsideUserInfoCardSection(),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                // 🔹 출근 보고 버튼: URL/로직 제거 후, 단순 바텀 시트
                                const Expanded(
                                  child: SimpleInsideReportButtonSection(),
                                ),
                                const SizedBox(width: 12),
                                // 🔹 출근하기 버튼: 기존 로직 제거 후, 단순 바텀 시트
                                const Expanded(
                                  child: SimpleInsideWorkButtonSection(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 1),
                            Center(
                              child: SizedBox(
                                height: 80,
                                child:
                                Image.asset('assets/images/pelican.png'),
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
                        switch (value) {
                          case 'logout':
                            _handleLogout(context);
                            break;
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
                  // 🔹 기존의 출근 시트 관련 오버레이/로딩은 이미 제거된 상태
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
