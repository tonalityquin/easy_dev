import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/sheets_config.dart';

// ✨ 변경: 온라인용 LogoutHelper 제거 → 오프라인 세션 삭제 전용 헬퍼 사용
import 'package:easydev/routes.dart';

import '../../offline_logout_helper.dart';
import 'commute_inside_package/offline_commute_inside_controller.dart';
import 'commute_inside_package/sections/offline_commute_inside_report_button_section.dart';
import 'commute_inside_package/sections/offline_commute_inside_work_button_section.dart';
import 'commute_inside_package/sections/offline_commute_inside_user_info_card_section.dart';
import 'commute_inside_package/sections/offline_commute_inside_header_widget_section.dart';

class OfflineCommuteInsideScreen extends StatefulWidget {
  const OfflineCommuteInsideScreen({super.key});

  @override
  State<OfflineCommuteInsideScreen> createState() => _OfflineCommuteInsideScreenState();
}

class _OfflineCommuteInsideScreenState extends State<OfflineCommuteInsideScreen> {
  final controller = OfflineCommuteInsideController();

  // ✅ 세션(메모리) 보관으로 변경: 영구 저장 제거(SharedPreferences 제거)
  String? kakaoUrl;
  bool loadingUrl = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    controller.initialize(context);

    // 최초 진입 시 1회 자동 라우팅
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCustomKakaoUrl(); // 이제는 세션 메모리 초기값만 세팅
      if (!mounted) return;

      final userState = context.read<UserState>();
      if (userState.isWorking) {
        controller.redirectIfWorking(context, userState);
      }
    });
  }

  // ✅ 영구 저장 삭제: 초기값 세팅만 하고 로딩 종료
  Future<void> _loadCustomKakaoUrl() async {
    if (!mounted) return;
    setState(() {
      kakaoUrl = null; // 초기값은 없음(세션 보관)
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
          initialChildSize: 1.0,
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

  // ✅ 영구 저장(SharedPreferences) → 세션(상태) 변경
  void _handleChangeUrl(BuildContext context) async {
    final urlTextCtrl = TextEditingController(text: kakaoUrl ?? '');

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
              if (!mounted) return;
              setState(() {
                kakaoUrl = url.isNotEmpty ? url : null; // 메모리에만 보관
              });
              Navigator.pop(context);
              showSuccessSnackbar(context, 'URL이 저장되었습니다. (앱 재시작 시 초기화)');
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
    // ✨ 변경: 오프라인 세션 삭제 후 오프라인 로그인으로 복귀
    await OfflineLogoutHelper.logoutAndGoToLogin(
      context,
      loginRoute: AppRoutes.offlineLogin,
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
                  SingleChildScrollView(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const OfflineCommuteInsideHeaderWidgetSection(),
                            const OfflineCommuteInsideUserInfoCardSection(),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: OfflineCommuteInsideReportButtonSection(
                                    loadingUrl: loadingUrl,
                                    kakaoUrl: kakaoUrl,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OfflineCommuteInsideWorkButtonSection(
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
                              Icon(Icons.edit_location_alt, color: Colors.blueAccent),
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
