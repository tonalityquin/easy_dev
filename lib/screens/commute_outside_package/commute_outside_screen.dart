import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../states/user/user_state.dart';
import '../../utils/snackbar_helper.dart';
import 'debugs/clock_in_debug_firestore_logger.dart';
import 'commute_outside_controller.dart';
import 'sections/report_button_section.dart';
import 'sections/work_button_section.dart';
import 'sections/user_info_card_section.dart';
import 'sections/header_widget_section.dart';

class CommuteOutsideScreen extends StatefulWidget {
  const CommuteOutsideScreen({super.key});

  @override
  State<CommuteOutsideScreen> createState() => _CommuteOutsideScreenState();
}

class _CommuteOutsideScreenState extends State<CommuteOutsideScreen> {
  final controller = CommuteOutsideController();
  final logger = ClockInDebugFirestoreLogger();

  String? kakaoUrl;
  bool loadingUrl = true;
  bool _isLoading = false;

  void _toggleLoading() {
    setState(() {
      _isLoading = !_isLoading;
    });
  }

  @override
  void initState() {
    super.initState();
    logger.log('ClockInWorkScreen.initState() 호출됨', level: 'called');
    controller.initialize(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomKakaoUrl();
    });
  }

  Future<void> _loadCustomKakaoUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('custom_kakao_url');

    setState(() {
      kakaoUrl = savedUrl?.isNotEmpty == true ? savedUrl : null;
      loadingUrl = false;
    });

    if (savedUrl != null && savedUrl.isNotEmpty) {
      logger.log('✅ 사용자 지정 URL 사용: $savedUrl', level: 'info');
    } else {
      logger.log('❌ 사용자 URL 없음', level: 'warn');
    }
  }

  void _handleChangeUrl(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = TextEditingController(text: prefs.getString('custom_kakao_url') ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('출근 보고용 URL을 입력하세요.', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: '카카오톡 오픈채팅 URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  final url = controller.text.trim();
                  await prefs.setString('custom_kakao_url', url);
                  logger.log('🔧 사용자 URL 저장됨: $url', level: 'success');
                  if (!mounted) return;
                  setState(() {
                    kakaoUrl = url;
                  });
                  Navigator.pop(context);
                  showSuccessSnackbar(context, 'URL이 저장되었습니다.');
                },
                child: const Text('저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      logger.log('로그아웃 시도 중...', level: 'called');
      final userState = context.read<UserState>();
      await FlutterForegroundTask.stopService();
      await userState.clearUserToPhone();
      await Future.delayed(const Duration(milliseconds: 500));
      logger.log('✅ 로그아웃 성공', level: 'success');
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    } catch (e) {
      logger.log('❌ 로그아웃 실패: $e', level: 'error');
      if (context.mounted) {
        showFailedSnackbar(context, '로그아웃 실패: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          // 화면 유지 요구사항에 따라 자동 리다이렉트 제거
          // if (userState.isWorking) {
          //   controller.redirectIfWorking(context, userState);
          // }

          return SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const HeaderWidgetSection(),
                          const UserInfoCardSection(),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: ReportButtonSection(
                                  loadingUrl: loadingUrl,
                                  kakaoUrl: kakaoUrl,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: WorkButtonSection(
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
                          const SizedBox(height: 12),
                          // ▼ 휴식해요 / 퇴근해요 버튼
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.free_breakfast),
                                  label: const Text(
                                    '휴식해요',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    minimumSize: const Size.fromHeight(55),
                                    padding: EdgeInsets.zero,
                                    side: const BorderSide(color: Colors.grey, width: 1.0),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () async {
                                    await controller.handleBreakPressed(
                                      context,
                                      context.read<UserState>(),
                                      _toggleLoading,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.exit_to_app),
                                  label: const Text(
                                    '퇴근해요',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    minimumSize: const Size.fromHeight(55),
                                    padding: EdgeInsets.zero,
                                    side: const BorderSide(color: Colors.grey, width: 1.0),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () async {
                                    await controller.handleLeavePressed(
                                      context,
                                      context.read<UserState>(),
                                      _toggleLoading,
                                      exitAppAfter: true, // 필요시 false로 바꾸고 네비게이션 처리
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
                // ▼ 옵션 A: 메뉴 복구 (두 핸들러가 실제로 참조됨)
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
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('로그아웃'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'changeUrl',
                        child: Row(
                          children: [
                            Icon(Icons.edit_location_alt, color: Colors.blueAccent),
                            SizedBox(width: 8),
                            Text('경로 변경'),
                          ],
                        ),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert),
                  ),
                ),
                // 화면 유지 요구사항에 맞게 isWorking에 따른 전역 오버레이 제거, 로딩일 때만 표시
                if (_isLoading)
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
    );
  }
}
