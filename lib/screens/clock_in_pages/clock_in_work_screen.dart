import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import 'debugs/clock_in_debug_bottom_sheet.dart';
import 'debugs/clock_in_debug_firestore_logger.dart'; // ✅ 로컬 디버깅 로거 추가
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
  final logger = ClockInDebugFirestoreLogger(); // ✅

  String? kakaoUrl;
  bool loadingUrl = true;

  @override
  void initState() {
    super.initState();

    logger.log('ClockInWorkScreen.initState() 호출됨', level: 'called');
    controller.initialize(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryLoadKakaoUrl();
    });
  }

  Future<void> _tryLoadKakaoUrl() async {
    final userState = context.read<UserState>();

    if (userState.isLoading || userState.division.isEmpty) {
      logger.log('UserState 로딩 중... 재시도 예약', level: 'info');
      await Future.delayed(const Duration(milliseconds: 300));
      _tryLoadKakaoUrl();
      return;
    }

    _loadKakaoUrlWithCache(userState, context.read<AreaState>());
  }

  Future<void> _loadKakaoUrlWithCache(
      UserState userState,
      AreaState areaState,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    final division = userState.division.trim();
    final currentArea = userState.user?.selectedArea?.trim() ?? '';

    logger.log('_loadKakaoUrlWithCache 호출 - division=$division, area=$currentArea', level: 'called');

    if (division.isEmpty || currentArea.isEmpty) {
      logger.log('❌ division 또는 area 값 없음', level: 'error');
      setState(() {
        kakaoUrl = null;
        loadingUrl = false;
      });
      return;
    }

    final cacheKey = 'cached_kakao_url_${division}_$currentArea';
    final cached = prefs.getString(cacheKey);

    if (cached != null && cached.isNotEmpty) {
      logger.log('✅ 캐시된 URL 사용됨: $cached', level: 'info');
      setState(() {
        kakaoUrl = cached;
        loadingUrl = false;
      });
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('export_link')
          .where('division', isEqualTo: division)
          .where('area', isEqualTo: currentArea)
          .where('purpose', isEqualTo: 'clockin')
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final url = query.docs.first.data()['url'] as String?;
        if (url != null && url.isNotEmpty) {
          logger.log('✅ Firestore에서 URL 로드 성공: $url', level: 'success');
          await prefs.setString(cacheKey, url);
          setState(() {
            kakaoUrl = url;
            loadingUrl = false;
          });
        } else {
          logger.log('⚠️ URL 필드 비어있음', level: 'warn');
          setState(() {
            kakaoUrl = null;
            loadingUrl = false;
          });
        }
      } else {
        logger.log('⚠️ Firestore에 export_link 문서 없음', level: 'warn');
        setState(() {
          kakaoUrl = null;
          loadingUrl = false;
        });
      }
    } catch (e) {
      logger.log('❌ Firestore URL 로드 실패: $e', level: 'error');
      if (kakaoUrl == null) {
        setState(() {
          kakaoUrl = null;
          loadingUrl = false;
        });
      }
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      logger.log('로그아웃 시도 중...', level: 'called');
      final userState = Provider.of<UserState>(context, listen: false);

      await FlutterForegroundTask.stopService();
      await userState.clearUserToPhone();
      await Future.delayed(const Duration(milliseconds: 500));
      logger.log('✅ 로그아웃 성공', level: 'success');
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    } catch (e) {
      logger.log('❌ 로그아웃 실패: $e', level: 'error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그아웃 실패: $e')),
        );
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
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const HeaderWidget(),
                          const ClockInFetchPlateCountWidget(),
                          const UserInfoCard(),
                          const SizedBox(height: 32),
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
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.bug_report, size: 18),
                              label: const Text("디버깅"),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => const ClockInDebugBottomSheet(),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 32),
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
                      const PopupMenuItem<String>(
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
    );
  }
}
