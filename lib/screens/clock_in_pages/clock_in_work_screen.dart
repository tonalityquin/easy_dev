import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import 'debugs/clock_in_debug_bottom_sheet.dart';
import 'clock_in_controller.dart';
import 'sections/fetch_plate_count_widget.dart';
import 'sections/work_button_widget.dart';
import 'sections/user_info_card.dart';

class ClockInWorkScreen extends StatefulWidget {
  const ClockInWorkScreen({super.key});

  @override
  State<ClockInWorkScreen> createState() => _ClockInWorkScreenState();
}

class _ClockInWorkScreenState extends State<ClockInWorkScreen> {
  final controller = ClockInController();

  String? kakaoUrl;
  bool loadingUrl = true;

  @override
  void initState() {
    super.initState();
    controller.initialize(context);

    // ✅ 화면이 렌더된 뒤 상태를 읽도록 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryLoadKakaoUrl();
    });
  }

  /// UserState 데이터가 로딩될 때까지 기다린 뒤 Firestore 로드
  Future<void> _tryLoadKakaoUrl() async {
    final userState = context.read<UserState>();
    final areaState = context.read<AreaState>();

    if (userState.isLoading || userState.division.isEmpty) {
      debugPrint('⏳ UserState 로딩 중... 잠시 대기');
      await Future.delayed(const Duration(milliseconds: 300));
      _tryLoadKakaoUrl();
      return;
    }

    _loadKakaoUrlWithCache(userState, areaState);
  }

  /// Firestore + SharedPreferences 캐싱
  Future<void> _loadKakaoUrlWithCache(
      UserState userState,
      AreaState areaState,
      ) async {
    final prefs = await SharedPreferences.getInstance();

    final division = userState.division.trim();
    final currentArea = userState.user?.selectedArea?.trim() ?? '';

    debugPrint('🚀 _loadKakaoUrlWithCache 시작 - division=$division, currentArea=$currentArea');

    if (division.isEmpty || currentArea.isEmpty) {
      debugPrint('❌ division이나 currentArea 정보가 없습니다.');
      setState(() {
        kakaoUrl = null;
        loadingUrl = false;
      });
      return;
    }

    final cacheKey = 'cached_kakao_url_${division}_$currentArea';
    final cached = prefs.getString(cacheKey);

    if (cached != null && cached.isNotEmpty) {
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
        final doc = query.docs.first;
        final url = doc.data()['url'] as String?;
        if (url != null && url.isNotEmpty) {
          await prefs.setString(cacheKey, url);
          setState(() {
            kakaoUrl = url;
            loadingUrl = false;
          });
        } else {
          setState(() {
            kakaoUrl = null;
            loadingUrl = false;
          });
        }
      } else {
        setState(() {
          kakaoUrl = null;
          loadingUrl = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Firestore URL 로드 실패: $e');
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
      final userState = Provider.of<UserState>(context, listen: false);

      await FlutterForegroundTask.stopService();
      await userState.clearUserToPhone();
      await Future.delayed(const Duration(milliseconds: 500));
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    } catch (e) {
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
                          const SizedBox(height: 96),
                          SizedBox(
                            height: 120,
                            child: Image.asset('assets/images/belivus_logo.PNG'),
                          ),
                          const SizedBox(height: 48),
                          Center(
                            child: Text(
                              '출근 전 사용자 정보 확인',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const UserInfoCard(),
                          const FetchPlateCountWidget(),
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.assignment),
                                  label: loadingUrl ? const Text('로딩 중...') : const Text('보고 작성'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: const BorderSide(color: Colors.grey),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: loadingUrl
                                      ? null
                                      : () async {
                                    if (kakaoUrl == null || kakaoUrl!.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('카카오톡 URL이 없습니다.'),
                                        ),
                                      );
                                      return;
                                    }
                                    final intent = AndroidIntent(
                                      action: 'action_view',
                                      data: kakaoUrl!,
                                      package: 'com.android.chrome',
                                    );
                                    try {
                                      await intent.launch();
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('크롬으로 열 수 없습니다: $e'),
                                          ),
                                        );
                                      }
                                    }
                                  },
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
