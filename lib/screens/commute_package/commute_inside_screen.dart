import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
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
    } else {}
  }

  void _handleChangeUrl(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = TextEditingController(
      text: prefs.getString('custom_kakao_url') ?? '',
    );

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

                  // ✅ await 이후 BuildContext 안전성 체크
                  if (!context.mounted) return;

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
      final userState = context.read<UserState>();
      await FlutterForegroundTask.stopService();
      await userState.clearUserToPhone();
      await Future.delayed(const Duration(milliseconds: 500));
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    } catch (e) {
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
    );
  }
}
