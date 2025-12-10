// lib/screens/simple_package/simple_inside_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../states/user/user_state.dart';
import '../../../utils/init/logout_helper.dart';
import '../../services/endtime_reminder_service.dart';
import 'simple_inside_package/simple_inside_controller.dart';
import 'simple_inside_package/widgets/sections/simple_inside_report_button_section.dart';
import 'simple_inside_package/widgets/sections/simple_inside_work_button_section.dart';
import 'simple_inside_package/widgets/sections/simple_inside_user_info_card_section.dart';
import 'simple_inside_package/widgets/sections/simple_inside_header_widget_section.dart';
import 'simple_inside_package/widgets/sections/simple_inside_clock_out_button_section.dart';
import 'simple_inside_package/widgets/sections/simple_inside_document_box_button_section.dart';
import 'simple_inside_package/widgets/sections/simple_inside_document_form_button_section.dart';
import 'simple_inside_package/widgets/sections/simple_inside_punch_recorder_section.dart';

/// 약식 출퇴근 화면 모드:
/// - common: 기존 약식 화면(업무 보고 / 출근하기 / 퇴근하기 / 서류함 열기)
/// - team  : 필드 유저 전용
///   · 출퇴근/휴게 기록은 "출퇴근 기록기 카드"에서 펀칭으로만 입력
///   · 하단 버튼에는 결제 서류 버튼만 노출
enum SimpleInsideMode {
  common,
  team,
}

class SimpleInsideScreen extends StatefulWidget {
  const SimpleInsideScreen({
    super.key,
    this.mode, // 외부에서 명시적으로 넘기지 않으면 null
  });

  /// 화면 모드
  /// - null 이면 UserState.user.role 기반으로 자동 결정
  /// - 값이 있으면 외부 지정 모드를 그대로 사용
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

  /// "어제 출근만 하고 퇴근 안 누른 상태" 등을 오늘 앱 실행 시 자동으로 정리
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

  // 좌측 상단(11시) 고정 라벨: 'simple screen'
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

  /// 실제 사용할 모드를 결정하는 헬퍼
  /// 1) widget.mode 가 지정되어 있으면 그대로 사용
  /// 2) null 이면 UserState.user.role 기반으로 자동 결정
  SimpleInsideMode _resolveMode(UserState userState) {
    // 1) 외부에서 명시적으로 모드가 들어온 경우
    if (widget.mode != null) {
      return widget.mode!;
    }

    // 2) role 기반 자동 모드 결정
    //    - userState.user 가 null 일 수도 있다는 전제하에 안전하게 처리
    String role = '';

    final user = userState.user; // UserModel? 라고 가정
    if (user != null) {
      // user.role 이 String 또는 String? 일 수 있으므로 한 번 더 방어적으로 처리
      final dynamic rawRole = user.role;
      if (rawRole is String) {
        role = rawRole.trim();
      } else if (rawRole != null) {
        role = rawRole.toString().trim();
      }
    }

    debugPrint('[SimpleInsideScreen] resolved role="$role"');

    if (role == 'fieldCommon') {
      // 필드 유저(팀원) 모드
      return SimpleInsideMode.team;
    }

    // 그 외는 common 모드
    return SimpleInsideMode.common;
  }

  @override
  Widget build(BuildContext context) {
    // 이 화면에서만 뒤로가기로 앱 종료되지 않도록 차단 (스낵바 안내 없음)
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Consumer<UserState>(
          builder: (context, userState, _) {
            // 여기서 UserState 기준으로 모드 결정
            final mode = _resolveMode(userState);

            // ✅ 유저 메타 정보 추출
            final user = userState.user;
            if (user == null) {
              // 로그인 정보가 아직 안 올라온 경우 등 방어
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            // 필드명은 실제 UserModel 정의에 맞게 사용
            final String userId = user.id;      // 예: "01090351868-belivus"
            final String userName = user.name;  // 예: "조성오"

            // 🔹 현재 UserModel 에 area / division 이 없으므로
            //    Firestore 보조 로그용으로만 빈 문자열을 전달
            const String area = '';
            const String division = '';

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

                            // 🔥 공통/팀원 모드에 따라 다른 카드 사용
                            if (mode == SimpleInsideMode.team)
                            // 필드 유저: 출퇴근 기록기 카드로만 펀칭
                              SimpleInsidePunchRecorderSection(
                                userId: userId,
                                userName: userName,
                                area: area,
                                division: division,
                              )
                            else
                            // 일반 모드: 근무자 정보 카드 유지
                              const SimpleInsideUserInfoCardSection(),

                            const SizedBox(height: 6),

                            // 모드별 버튼 레이아웃 분기
                            if (mode == SimpleInsideMode.common)
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

                  // 우측 상단 메뉴(로그아웃만)
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
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 공통(common) 모드 버튼 그리드
/// - 1행: 업무 보고 / 출근하기
/// - 2행: 퇴근하기 / 서류함 열기
class _CommonModeButtonGrid extends StatelessWidget {
  const _CommonModeButtonGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Row(
          children: [
            Expanded(
              child: SimpleInsideReportButtonSection(),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SimpleInsideWorkButtonSection(),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SimpleInsideClockOutButtonSection(),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SimpleInsideDocumentBoxButtonSection(),
            ),
          ],
        ),
      ],
    );
  }
}

/// 팀원(team / fieldCommon) 모드 버튼 그리드
/// - 출근/휴게/퇴근은 상단 "출퇴근 기록기" 카드에서만 펀칭
/// - 하단에는 결제 서류 버튼만 유지
class _TeamModeButtonGrid extends StatelessWidget {
  const _TeamModeButtonGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Row(
          children: [
            Expanded(
              child: SimpleInsideDocumentFormButtonSection(),
            ),
          ],
        ),
      ],
    );
  }
}
