// lib/screens/simple_package/simple_inside_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ (추가) Google Sheets API
import 'package:googleapis/sheets/v4.dart' as sheets;
// ✅ (추가) Google Sheets API 인증 세션
import '../../../utils/google_auth_session.dart';

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

/// ✅ 공지 스프레드시트 저장 키 (SharedPreferences)
const String _kNoticeSpreadsheetIdKey = 'notice_spreadsheet_id_v1';

/// ✅ 공지 시트명 고정: noti
const String _kNoticeSheetName = 'noti';

/// ✅ 공지 Range (noti 시트 A열 1~50행)
const String _kNoticeSpreadsheetRange = '$_kNoticeSheetName!A1:A50';

Future<sheets.SheetsApi> _sheetsApi() async {
  final client = await GoogleAuthSession.instance.safeClient();
  return sheets.SheetsApi(client);
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

  // ✅ 공지 로딩 상태
  bool _noticeLoading = false;
  String? _noticeError;
  List<String> _noticeLines = const [];
  String _noticeSheetId = '';

  final ScrollController _noticeScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    controller.initialize(context);

    // ✅ 공지 스프레드시트 ID 부트스트랩 + 로드
    _bootstrapNoticeSheetId();

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

  @override
  void dispose() {
    _noticeScroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrapNoticeSheetId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_kNoticeSpreadsheetIdKey) ?? '').trim();

      if (!mounted) return;
      setState(() {
        _noticeSheetId = saved;
        _noticeError = null;
        _noticeLines = const [];
      });

      if (saved.isEmpty) return;
      await _loadNotice();
    } catch (_) {
      // 부트스트랩 실패는 공지 영역에만 영향 → 조용히 무시
    }
  }

  Future<void> _loadNotice() async {
    final id = _noticeSheetId.trim();
    if (id.isEmpty) {
      if (!mounted) return;
      setState(() {
        _noticeLoading = false;
        _noticeError = null;
        _noticeLines = const [];
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _noticeLoading = true;
      _noticeError = null;
    });

    try {
      final api = await _sheetsApi();

      // ✅ noti 시트에서 읽음
      final resp = await api.spreadsheets.values.get(id, _kNoticeSpreadsheetRange);

      final values = resp.values ?? const [];

      // rows -> text lines
      final lines = <String>[];
      for (final row in values) {
        final rowStrings = row.map((c) => (c ?? '').toString().trim()).toList();
        final joined = rowStrings.where((s) => s.isNotEmpty).join(' ');
        if (joined.isNotEmpty) lines.add(joined);
      }

      if (!mounted) return;
      setState(() {
        _noticeLines = lines;
        _noticeLoading = false;
        _noticeError = null;
      });
    } catch (e) {
      final msg = GoogleAuthSession.isInvalidTokenError(e)
          ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
          : '공지 불러오기 실패: $e';

      if (!mounted) return;
      setState(() {
        _noticeLoading = false;
        _noticeError = msg;
        _noticeLines = const [];
      });
    }
  }

  Widget _buildNoticeSection(BuildContext context) {
    final hasId = _noticeSheetId.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.campaign_outlined,
                  size: 18,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '공지',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                tooltip: '새로고침',
                onPressed: hasId ? _loadNotice : null,
                icon: _noticeLoading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasId)
            const Text(
              '공지 스프레드시트 ID가 설정되어 있지 않습니다.\n(설정 화면에서 notice_spreadsheet_id_v1 저장 후 적용됩니다.)',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            )
          else if (_noticeError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _noticeError!,
                  style: const TextStyle(fontSize: 13, color: Colors.redAccent),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadNotice,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('다시 불러오기'),
                ),
              ],
            )
          else if (_noticeLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_noticeLines.isEmpty)
                const Text(
                  '공지 내용이 없습니다.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: Scrollbar(
                        controller: _noticeScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _noticeScroll,
                          child: Text(
                            _noticeLines.map((e) => '• $e').join('\n'),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
        ],
      ),
    );
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
                            const SizedBox(height: 12),

                            // ✅ (추가) PunchRecorder 상단 공지
                            _buildNoticeSection(context),
                            const SizedBox(height: 12),

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
