import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../states/user/user_state.dart';
import '../../utils/snackbar_helper.dart';
import 'debugs/clock_in_debug_firestore_logger.dart';
import 'clock_in_controller.dart';
import 'sections/clock_in_fetch_plate_count_widget.dart';
import 'sections/report_button_widget.dart';
import 'sections/work_button_widget.dart';
import 'sections/user_info_card.dart';
import 'sections/header_widget.dart';

class ClockInWorkScreen extends StatefulWidget {
  const ClockInWorkScreen({super.key});

  @override
  State<ClockInWorkScreen> createState() => _ClockInWorkScreenState();
}

class _ClockInWorkScreenState extends State<ClockInWorkScreen> {
  final controller = ClockInController();
  final logger = ClockInDebugFirestoreLogger();

  String? kakaoUrl;
  bool loadingUrl = true;

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

    if (savedUrl != null && savedUrl.isNotEmpty) {
      logger.log('✅ 사용자 지정 URL 사용: $savedUrl', level: 'info');
      setState(() {
        kakaoUrl = savedUrl;
        loadingUrl = false;
      });
    } else {
      logger.log('❌ 사용자 URL 없음', level: 'warn');
      setState(() {
        kakaoUrl = null;
        loadingUrl = false;
      });
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
          if (userState.isWorking) {
            controller.redirectIfWorking(context, userState);
          }

          return SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const HeaderWidget(),
                          const ClockInFetchPlateCountWidget(),
                          const UserInfoCard(),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: ReportButtonWidget(
                                  loadingUrl: loadingUrl,
                                  kakaoUrl: kakaoUrl,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: WorkButtonWidget(controller: controller),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
              ],
            ),
          );
        },
      ),
    );
  }
}
