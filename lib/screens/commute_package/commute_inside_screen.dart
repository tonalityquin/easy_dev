// lib/screens/commute_package/commute_inside_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/api/sheets_config.dart';
import '../../../utils/init/logout_helper.dart';
import '../../services/endtime_reminder_service.dart';
import 'commute_inside_package/commute_inside_controller.dart';
import 'commute_inside_package/sections/commute_inside_report_button_section.dart';
import 'commute_inside_package/sections/commute_inside_work_button_section.dart';
import 'commute_inside_package/sections/commute_inside_user_info_card_section.dart';
import 'commute_inside_package/sections/commute_inside_header_widget_section.dart';

class CommuteInsideScreen extends StatefulWidget {
  const CommuteInsideScreen({super.key});

  @override
  State<CommuteInsideScreen> createState() => _CommuteInsideScreenState();
}

class _CommuteInsideScreenState extends State<CommuteInsideScreen> {
  final controller = CommuteInsideController();
  String? kakaoUrl;
  bool loadingUrl = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    controller.initialize(context);

    // OPTION A: 자동 라우팅은 최초 진입 시 1회만 수행
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCustomKakaoUrl();
      if (!mounted) return;

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

      // 3) 최종 상태 기준으로만 자동 라우팅
      if (userState.isWorking) {
        controller.redirectIfWorking(context, userState);
      }
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

  Future<void> _loadCustomKakaoUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('custom_kakao_url');

    if (!mounted) return;
    setState(() {
      kakaoUrl = (savedUrl != null && savedUrl.isNotEmpty) ? savedUrl : null;
      loadingUrl = false;
    });
  }

  /// 공용: 전체 높이(최상단까지)로 올라오는 흰색 바텀시트를 띄우는 헬퍼
  Future<T?> _showFullHeightSheet<T>({
    required WidgetBuilder childBuilder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 1.0, // 최상단까지
          minChildSize: 0.25,
          maxChildSize: 1.0,
          builder: (ctx, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  // 키보드가 올라올 때 안전하게 하단 패딩 확보
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: childBuilder(ctx),
              ),
            );
          },
        );
      },
    );
  }

  void _handleChangeUrl(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final urlTextCtrl = TextEditingController(
      text: prefs.getString('custom_kakao_url') ?? '',
    );

    await _showFullHeightSheet<void>(
      childBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '출근 보고용 URL을 입력하세요.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: urlTextCtrl,
            decoration: const InputDecoration(
              labelText: '카카오톡 오픈채팅 URL',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              final url = urlTextCtrl.text.trim();
              await prefs.setString('custom_kakao_url', url);

              if (!mounted) return;
              setState(() {
                kakaoUrl = url.isNotEmpty ? url : null;
              });

              Navigator.pop(context);
              showSuccessSnackbar(context, 'URL이 저장되었습니다.');
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSetCommuteSheetId(BuildContext context) async {
    final current = await SheetsConfig.getCommuteSheetId();
    final textCtrl = TextEditingController(text: current ?? '');

    await _showFullHeightSheet<void>(
      childBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '출근/퇴근/휴게 스프레드시트 ID 입력',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: textCtrl,
            decoration: const InputDecoration(
              labelText: 'Google Sheets ID 또는 전체 URL',
              helperText: 'URL 전체를 붙여넣어도 ID만 추출됩니다.',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              final raw = textCtrl.text.trim();
              if (raw.isEmpty) return;

              final id = SheetsConfig.extractSpreadsheetId(raw);
              await SheetsConfig.setCommuteSheetId(id);

              if (!mounted) return;
              Navigator.pop(context);
              showSuccessSnackbar(context, '출근 시트 ID가 저장되었습니다.');
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    // 앱 종료 대신 공통 정책: 허브(Selector)로 이동 + prefs('mode') 초기화
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(milliseconds: 500),
    );
  }

  // ⬇️ 좌측 상단(11시) 고정 라벨: 'commute screen'
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
          label: 'screen_tag: commute screen',
          child: Text('commute screen', style: style),
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
            // 자동 라우팅은 initState의 addPostFrameCallback에서 1회 수행

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
                            const CommuteInsideHeaderWidgetSection(),
                            const CommuteInsideUserInfoCardSection(),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: CommuteInsideReportButtonSection(
                                    loadingUrl: loadingUrl,
                                    kakaoUrl: kakaoUrl,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CommuteInsideWorkButtonSection(
                                    controller: controller,
                                    onLoadingChanged: (value) {
                                      setState(() {
                                        _isLoading = value;
                                      });
                                    },
                                  ),
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
                          case 'changeUrl':
                            _handleChangeUrl(context);
                            break;
                          case 'setCommuteSheet':
                            _handleSetCommuteSheetId(context);
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
                        PopupMenuItem(
                          value: 'changeUrl',
                          child: Row(
                            children: [
                              Icon(Icons.edit_location_alt,
                                  color: Colors.blueAccent),
                              SizedBox(width: 8),
                              Text('경로 변경'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'setCommuteSheet',
                          child: Row(
                            children: [
                              Icon(Icons.assignment_add, color: Colors.green),
                              SizedBox(width: 8),
                              Text('출근 시트 삽입'),
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
