import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/snackbar_helper.dart';
import '../../utils/api/email_config.dart';

// ✅ NEW: 공용 앱 종료 서비스
import '../../utils/app_exit_service.dart';

// ⬅️ 오버레이 모드 설정
import '../../utils/overlay_mode_config.dart';

// ✅ commute_true_false Firestore 기록 On/Off(기기별, 기본 OFF + 유지)
import '../../utils/commute_true_false_mode_config.dart';

// ✅ (추가) 입차 완료 테이블 "실시간 탭" On/Off(기기별, 기본 OFF + 유지)
import '../../utils/parking_completed_realtime_tab_mode_config.dart';

// ✅ (추가) 출차 요청 테이블 "실시간 탭" On/Off(기기별, 기본 OFF + 유지)
import '../../utils/departure_requests_realtime_tab_mode_config.dart';

// ✅ (추가) 입차 요청 테이블 "실시간 탭" On/Off(기기별, 기본 OFF + 유지)
import '../../utils/parking_requests_realtime_tab_mode_config.dart';

// ✅ (추가) 스프레드시트 ID/URL에서 ID 추출 헬퍼
import '../../utils/api/sheets_config.dart';

// ✅ (추가) Google Sheets API 인증 세션
import '../../utils/google_auth_session.dart';

/// ✅ 공지 스프레드시트 저장 키 (SharedPreferences)
const String _kNoticeSpreadsheetIdKey = 'notice_spreadsheet_id_v1';

/// ✅ (중요) 공지 시트명 고정: noti
const String _kNoticeSheetName = 'noti';

/// ✅ (중요) 공지 Range (noti 시트 A열 1~50행)
const String _kNoticeSpreadsheetRange = '$_kNoticeSheetName!A1:A50';

/// ✅ (추가) View 삽입(Write) 게이트 키(기기별, 기본 OFF)
/// - Header 단일 스위치에서 "탭(접근)" + "삽입(동기화 쓰기)"를 함께 ON/OFF 동기화
const String _kParkingRequestsWriteEnabledKey = 'parking_requests_realtime_write_enabled_v1';
const String _kParkingCompletedWriteEnabledKey = 'parking_completed_realtime_write_enabled_v1';
const String _kDepartureRequestsWriteEnabledKey = 'departure_requests_realtime_write_enabled_v1';

/// ✅ 공지 시트 ID 변경을 Header와 Settings Sheet 사이에 공유하기 위한 노티파이어
final ValueNotifier<String> _noticeSheetIdNotifier = ValueNotifier<String>('');

Future<sheets.SheetsApi> _sheetsApi() async {
  final client = await GoogleAuthSession.instance.safeClient();
  return sheets.SheetsApi(client);
}

/// Option B(semantic tokens) 적용:
/// - Header 파일 내 UI 색상은 ColorScheme에서 파생된 "의미 토큰"만 사용한다.
/// - Colors.white/black/black54/redAccent 등의 하드코딩은 제거한다.
@immutable
class _HeaderTokens {
  const _HeaderTokens({
    required this.pageFg,
    required this.mutedFg,
    required this.border,
    required this.sectionBg,
    required this.sectionBorder,
    required this.iconBoxBg,
    required this.iconFg,
    required this.badgeRing,
    required this.badgeInnerBg,
    required this.badgeShadow,
    required this.badgeIcon,
    required this.sheetBg,
    required this.destructive,
  });

  final Color pageFg;
  final Color mutedFg;

  final Color border;

  final Color sectionBg;
  final Color sectionBorder;
  final Color iconBoxBg;
  final Color iconFg;

  final Color badgeRing;
  final Color badgeInnerBg;
  final Color badgeShadow;
  final Color badgeIcon;

  final Color sheetBg;

  /// destructive action color
  final Color destructive;

  factory _HeaderTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _HeaderTokens(
      pageFg: cs.onSurface,
      mutedFg: cs.onSurfaceVariant,
      border: cs.outlineVariant,
      sectionBg: cs.surfaceContainerLow,
      sectionBorder: cs.outlineVariant.withOpacity(.6),
      iconBoxBg: cs.surfaceContainerHighest.withOpacity(.7),
      iconFg: cs.onSurface,
      badgeRing: cs.primary,
      badgeInnerBg: cs.surface,
      badgeShadow: cs.shadow.withOpacity(0.08),
      badgeIcon: cs.onSurface,
      sheetBg: cs.surface,
      destructive: cs.error,
    );
  }
}

class Header extends StatefulWidget {
  const Header({super.key});

  @override
  State<Header> createState() => _HeaderState();
}

class _HeaderState extends State<Header> {
  bool _expanded = false;

  // ✅ 공지 로딩 상태
  bool _noticeLoading = false;
  String? _noticeError;
  List<String> _noticeLines = const [];
  String _noticeSheetId = '';

  final ScrollController _noticeScroll = ScrollController();

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  void initState() {
    super.initState();
    _noticeSheetIdNotifier.addListener(_onNoticeSheetIdChanged);
    _bootstrapNoticeSheetId();
  }

  @override
  void dispose() {
    _noticeSheetIdNotifier.removeListener(_onNoticeSheetIdChanged);
    _noticeScroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrapNoticeSheetId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_kNoticeSpreadsheetIdKey) ?? '').trim();
      _noticeSheetIdNotifier.value = saved;
    } catch (_) {
      // 부트스트랩 실패는 공지 영역에만 영향을 주므로 조용히 무시
    }
  }

  void _onNoticeSheetIdChanged() {
    final id = _noticeSheetIdNotifier.value.trim();
    if (_noticeSheetId == id) return;

    setState(() {
      _noticeSheetId = id;
      _noticeError = null;
      _noticeLines = const [];
    });

    // ID가 비어있으면 공지 영역은 안내만 표시
    if (_noticeSheetId.isEmpty) return;

    _loadNotice();
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
    final t = _HeaderTokens.of(context);
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final hasId = _noticeSheetId.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: t.sectionBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.sectionBorder),
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
                  color: t.iconBoxBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.campaign_outlined,
                  size: 18,
                  color: t.iconFg,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '공지',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: t.pageFg,
                  ),
                ),
              ),
              IconButton(
                tooltip: '새로고침',
                onPressed: hasId ? _loadNotice : null,
                icon: _noticeLoading
                    ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasId)
            Text(
              '공지 스프레드시트 ID가 설정되어 있지 않습니다.\n앱 설정에서 스프레드시트 ID를 입력하세요.',
              style: text.bodyMedium?.copyWith(fontSize: 13, color: t.pageFg),
            )
          else if (_noticeError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _noticeError!,
                  style: text.bodyMedium?.copyWith(fontSize: 13, color: cs.error),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadNotice,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('다시 불러오기'),
                ),
                const SizedBox(height: 2),
              ],
            )
          else if (_noticeLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: CircularProgressIndicator(color: cs.primary),
                ),
              )
            else if (_noticeLines.isEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '공지 내용이 없습니다.',
                      style: text.bodyMedium?.copyWith(fontSize: 13, color: t.pageFg),
                    ),
                  ],
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
                            style: text.bodyMedium?.copyWith(
                              fontSize: 13,
                              color: t.pageFg,
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

  @override
  Widget build(BuildContext context) {
    final t = _HeaderTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        _TopRow(
          expanded: _expanded,
          onToggle: _toggleExpanded,
        ),
        const SizedBox(height: 12),
        Text(
          '환영합니다',
          style: text.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: t.pageFg,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          '화살표 버튼을 누르면 해당 페이지로 진입합니다.',
          style: text.bodyMedium?.copyWith(color: t.mutedFg),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        _buildNoticeSection(context),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// 상단 가로 레이아웃: [왼쪽 버튼(앱 설정)] [배지(아이콘)] [오른쪽 버튼(앱 종료)]
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  // ✅ 앱 설정 진입 비밀번호
  static const String _kAppSettingsPassword = 'blsnc150119';

  Future<void> _openAppSettingsGate(BuildContext context) async {
    if (!expanded) return;

    final controller = TextEditingController();
    bool obscure = true;

    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final t = _HeaderTokens.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        final text = Theme.of(ctx).textTheme;
        final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setStateSheet) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: viewInsets + 16,
                  top: 16,
                ),
                child: Material(
                  color: t.sheetBg,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: t.iconBoxBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 20,
                                color: t.iconFg,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '앱 설정 접근',
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: t.pageFg,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: () => Navigator.of(ctx).pop(false),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '앱 설정에 진입하려면 비밀번호를 입력하세요.',
                          style: text.bodyMedium?.copyWith(fontSize: 13, color: t.pageFg),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: controller,
                          autofocus: true,
                          obscureText: obscure,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: '비밀번호',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.password_rounded),
                            suffixIcon: IconButton(
                              tooltip: obscure ? '표시' : '숨김',
                              onPressed: () => setStateSheet(() => obscure = !obscure),
                              icon: Icon(
                                obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => Navigator.of(ctx).pop(true),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('취소'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cs.primary,
                                  foregroundColor: cs.onPrimary,
                                ),
                                onPressed: () => Navigator.of(ctx).pop(true),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('확인'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (ok != true) return;

    final input = controller.text.trim();
    if (input != _kAppSettingsPassword) {
      showFailedSnackbar(context, '비밀번호가 올바르지 않습니다.');
      return;
    }

    HapticFeedback.selectionClick();
    showSuccessSnackbar(context, '앱 설정에 진입합니다.');
    await _openSheetsLinkSheet(context);
  }

  Future<void> _exitApp(BuildContext context) async {
    await AppExitService.exitApp(context);
  }

  Future<void> _openSheetsLinkSheet(BuildContext context) async {
    final emailCfg = await EmailConfig.load();
    final mailToCtrl = TextEditingController(text: emailCfg.to);

    OverlayMode currentOverlayMode = await OverlayModeConfig.getMode();

    final prefs = await SharedPreferences.getInstance();

    final initialized = prefs.getBool('overlay_mode_initialized_v2') ?? false;
    if (!initialized) {
      currentOverlayMode = OverlayMode.topHalf;
      await OverlayModeConfig.setMode(OverlayMode.topHalf);
      await prefs.setBool('overlay_mode_initialized_v2', true);
    }

    bool commuteTrueFalseEnabled = await CommuteTrueFalseModeConfig.isEnabled();

    // ✅ 탭 게이트(진입/갱신) 3종 로드
    bool parkingCompletedRealtimeTabEnabled = await ParkingCompletedRealtimeTabModeConfig.isEnabled();
    bool departureRequestsRealtimeTabEnabled = await DepartureRequestsRealtimeTabModeConfig.isEnabled();
    bool parkingRequestsRealtimeTabEnabled = await ParkingRequestsRealtimeTabModeConfig.isEnabled();

    // ✅ (추가) view 삽입(Write) 게이트 3종 로드(기기 로컬, 기본 OFF)
    bool parkingCompletedRealtimeWriteEnabled = prefs.getBool(_kParkingCompletedWriteEnabledKey) ?? false;
    bool departureRequestsRealtimeWriteEnabled = prefs.getBool(_kDepartureRequestsWriteEnabledKey) ?? false;
    bool parkingRequestsRealtimeWriteEnabled = prefs.getBool(_kParkingRequestsWriteEnabledKey) ?? false;

    final noticeIdCtrl = TextEditingController(
      text: (prefs.getString(_kNoticeSpreadsheetIdKey) ?? '').trim(),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final t = _HeaderTokens.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        final text = Theme.of(ctx).textTheme;

        Widget sectionBox({
          required IconData icon,
          required String title,
          required Widget child,
          Widget? trailing,
        }) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: t.sectionBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.sectionBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: t.iconBoxBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 20, color: t.iconFg),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: t.pageFg,
                        ),
                      ),
                    ),
                    if (trailing != null) trailing,
                  ],
                ),
                const SizedBox(height: 10),
                child,
              ],
            ),
          );
        }

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Material(
            color: t.sheetBg,
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 1.0,
              maxChildSize: 1.0,
              minChildSize: 0.4,
              builder: (ctx, sc) {
                return StatefulBuilder(
                  builder: (ctx, setSheetState) {
                    Widget buildOverlayPermissionSection() {
                      return sectionBox(
                        icon: Icons.bubble_chart_outlined,
                        title: '플로팅 버블(QuickOverlay) 권한',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '다른 앱 위에 플로팅 버블 또는 상단 포그라운드 패널(QuickOverlayHome)을 띄우기 위해서는 '
                                  '안드로이드 “다른 앱 위에 표시” 권한이 필요합니다.',
                              style: text.bodyMedium?.copyWith(fontSize: 13, color: t.pageFg),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.info_outline),
                                    onPressed: () async {
                                      if (!Platform.isAndroid) {
                                        if (!ctx.mounted) return;
                                        showFailedSnackbar(context, '안드로이드에서만 지원되는 기능입니다.');
                                        return;
                                      }
                                      try {
                                        final granted = await FlutterOverlayWindow.isPermissionGranted();
                                        if (!ctx.mounted) return;
                                        if (granted) {
                                          showSelectedSnackbar(
                                            context,
                                            '이미 “다른 앱 위에 표시” 권한이 허용되어 있습니다.',
                                          );
                                        } else {
                                          showFailedSnackbar(
                                            context,
                                            '현재 “다른 앱 위에 표시” 권한이 허용되지 않았습니다.',
                                          );
                                        }
                                      } catch (e) {
                                        if (!ctx.mounted) return;
                                        showFailedSnackbar(context, '권한 상태를 확인하는 중 오류가 발생했습니다: $e');
                                      }
                                    },
                                    label: const Text('현재 상태 확인'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.open_in_new_rounded),
                                    onPressed: () async {
                                      if (!Platform.isAndroid) {
                                        if (!ctx.mounted) return;
                                        showFailedSnackbar(context, '안드로이드에서만 지원되는 기능입니다.');
                                        return;
                                      }
                                      try {
                                        final already = await FlutterOverlayWindow.isPermissionGranted();
                                        if (already) {
                                          if (!ctx.mounted) return;
                                          showSelectedSnackbar(
                                            context,
                                            '이미 권한이 허용되어 있습니다.\n설정 앱에서 언제든지 변경할 수 있습니다.',
                                          );
                                          return;
                                        }

                                        final result = await FlutterOverlayWindow.requestPermission();

                                        if (!ctx.mounted) return;
                                        if (result == true) {
                                          showSuccessSnackbar(context, '권한이 허용되었습니다. 오버레이를 사용할 수 있습니다.');
                                        } else {
                                          showFailedSnackbar(
                                            context,
                                            '권한을 허용하지 않았습니다.\n필요 시 “설정 > 다른 앱 위에 표시”에서 직접 허용해 주세요.',
                                          );
                                        }
                                      } catch (e) {
                                        if (!ctx.mounted) return;
                                        showFailedSnackbar(context, '권한 설정 화면을 여는 중 오류가 발생했습니다: $e');
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: cs.primary,
                                      foregroundColor: cs.onPrimary,
                                    ),
                                    label: const Text('권한 설정 열기'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }

                    Widget buildOverlayModeSection() {
                      String labelFor(OverlayMode mode) {
                        switch (mode) {
                          case OverlayMode.topHalf:
                            return '상단 50% 포그라운드';
                          case OverlayMode.bubble:
                            return '플로팅 버블';
                        }
                      }

                      return sectionBox(
                        icon: Icons.view_sidebar_outlined,
                        title: '오버레이 형태 선택',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '앱이 백그라운드로 이동했을 때 사용할 오버레이 형태를 선택합니다.\n'
                                  '하나만 선택되며, 선택된 모드만 실행/종료 조건을 공유합니다.',
                              style: text.bodyMedium?.copyWith(fontSize: 13, color: t.pageFg),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text('플로팅 버블'),
                                  selected: currentOverlayMode == OverlayMode.bubble,
                                  onSelected: (selected) async {
                                    if (!selected) return;
                                    currentOverlayMode = OverlayMode.bubble;
                                    setSheetState(() {});
                                    await OverlayModeConfig.setMode(OverlayMode.bubble);

                                    try {
                                      if (await FlutterOverlayWindow.isActive()) {
                                        await FlutterOverlayWindow.shareData('__mode:bubble__');
                                        await FlutterOverlayWindow.shareData('__collapse__');
                                      }
                                    } catch (_) {}

                                    if (!ctx.mounted) return;
                                    showSuccessSnackbar(context, '플로팅 버블 모드가 선택되었습니다.');
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text('상단 50% 포그라운드'),
                                  selected: currentOverlayMode == OverlayMode.topHalf,
                                  onSelected: (selected) async {
                                    if (!selected) return;
                                    currentOverlayMode = OverlayMode.topHalf;
                                    setSheetState(() {});
                                    await OverlayModeConfig.setMode(OverlayMode.topHalf);

                                    try {
                                      if (await FlutterOverlayWindow.isActive()) {
                                        await FlutterOverlayWindow.shareData('__mode:topHalf__');
                                        await FlutterOverlayWindow.shareData('__collapse__');
                                      }
                                    } catch (_) {}

                                    if (!ctx.mounted) return;
                                    showSuccessSnackbar(context, '상단 50% 포그라운드 모드가 선택되었습니다.');
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '현재 선택: ${labelFor(currentOverlayMode)}',
                              style: text.bodySmall?.copyWith(color: t.mutedFg),
                            ),
                          ],
                        ),
                      );
                    }

                    Widget buildCommuteTrueFalseToggleSection() {
                      return sectionBox(
                        icon: Icons.cloud_upload_outlined,
                        title: '출근 시각 DB에 기록',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '이 설정은 “기기별(로컬)”로 저장됩니다.\n'
                                  'ON이면 출근 버튼을 누를 때 DB에 출근 시각(Timestamp)을 기록합니다.\n'
                                  'OFF이면 해당 DB 내 업데이트는 모두 건너뛰고, 로컬(SQLite) 기록만 수행합니다.',
                              style: text.bodyMedium?.copyWith(fontSize: 13, color: t.pageFg),
                            ),
                            const SizedBox(height: 10),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(commuteTrueFalseEnabled ? 'ON (기록함)' : 'OFF (기록 안 함)'),
                              subtitle: Text(
                                commuteTrueFalseEnabled
                                    ? '출근 시 최근 출근 날짜 업데이트가 실행됩니다.'
                                    : '출근 시 최근 출근 날짜 업데이트를 스킵합니다.',
                              ),
                              value: commuteTrueFalseEnabled,
                              onChanged: (v) async {
                                commuteTrueFalseEnabled = v;
                                setSheetState(() {});
                                await CommuteTrueFalseModeConfig.setEnabled(v);

                                if (!ctx.mounted) return;
                                showSuccessSnackbar(
                                  context,
                                  v
                                      ? '이 기기에서 출근 날짜 DB 기록을 ON으로 설정했습니다.'
                                      : '이 기기에서 출근 날짜 DB 기록을 OFF로 설정했습니다.',
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }

                    Widget buildRealtimeTabsToggleSection() {
                      final combined = parkingCompletedRealtimeTabEnabled ||
                          departureRequestsRealtimeTabEnabled ||
                          parkingRequestsRealtimeTabEnabled ||
                          parkingCompletedRealtimeWriteEnabled ||
                          departureRequestsRealtimeWriteEnabled ||
                          parkingRequestsRealtimeWriteEnabled;

                      return sectionBox(
                        icon: Icons.table_chart_outlined,
                        title: '실시간(view) 테이블 기능: 탭 + 삽입(Write) 동기화',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '이 설정은 “기기별(로컬)”로 저장됩니다.\n'
                                  'ON이면 입차 요청/입차 완료/출차 요청 실시간(view) 탭이 열리고, '
                                  '동시에 view 컬렉션 동기화 삽입/복구(Write)도 허용됩니다.\n'
                                  'OFF이면 세 테이블의 실시간 탭이 모두 잠기며, view 동기화 쓰기도 모두 중지됩니다.',
                              style: text.bodyMedium?.copyWith(fontSize: 13, color: t.pageFg),
                            ),
                            const SizedBox(height: 10),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                combined ? 'ON (탭 + 삽입(Write) 사용)' : 'OFF (탭 + 삽입(Write) 모두 중지)',
                              ),
                              subtitle: Text(
                                combined
                                    ? '세 테이블에서 실시간 탭 진입이 허용되고, view 동기화 쓰기도 허용됩니다.'
                                    : '세 테이블에서 실시간 탭 진입이 차단되며, view 동기화 쓰기도 차단됩니다.',
                              ),
                              value: combined,
                              onChanged: (v) async {
                                parkingCompletedRealtimeTabEnabled = v;
                                departureRequestsRealtimeTabEnabled = v;
                                parkingRequestsRealtimeTabEnabled = v;

                                parkingCompletedRealtimeWriteEnabled = v;
                                departureRequestsRealtimeWriteEnabled = v;
                                parkingRequestsRealtimeWriteEnabled = v;

                                setSheetState(() {});

                                await ParkingCompletedRealtimeTabModeConfig.setEnabled(v);
                                await DepartureRequestsRealtimeTabModeConfig.setEnabled(v);
                                await ParkingRequestsRealtimeTabModeConfig.setEnabled(v);

                                await prefs.setBool(_kParkingCompletedWriteEnabledKey, v);
                                await prefs.setBool(_kDepartureRequestsWriteEnabledKey, v);
                                await prefs.setBool(_kParkingRequestsWriteEnabledKey, v);

                                if (!ctx.mounted) return;
                                showSuccessSnackbar(
                                  context,
                                  v
                                      ? '이 기기에서 실시간(view) 탭 + 삽입(Write)을 모두 ON으로 설정했습니다.'
                                      : '이 기기에서 실시간(view) 탭 + 삽입(Write)을 모두 OFF로 설정했습니다.',
                                );
                              },
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '탭: 출차요청=${departureRequestsRealtimeTabEnabled ? "ON" : "OFF"}'
                                  ' / 입차요청=${parkingRequestsRealtimeTabEnabled ? "ON" : "OFF"}'
                                  ' / 입차완료=${parkingCompletedRealtimeTabEnabled ? "ON" : "OFF"}\n'
                                  '삽입(Write): 출차요청=${departureRequestsRealtimeWriteEnabled ? "ON" : "OFF"}'
                                  ' / 입차요청=${parkingRequestsRealtimeWriteEnabled ? "ON" : "OFF"}'
                                  ' / 입차완료=${parkingCompletedRealtimeWriteEnabled ? "ON" : "OFF"}',
                              style: text.bodySmall?.copyWith(color: t.mutedFg),
                            ),
                          ],
                        ),
                      );
                    }

                    Widget buildNoticeSpreadsheetSection() {
                      return sectionBox(
                        icon: Icons.campaign_outlined,
                        title: '공지 스프레드시트 설정',
                        trailing: IconButton(
                          tooltip: '초기화(삭제)',
                          onPressed: () async {
                            await prefs.remove(_kNoticeSpreadsheetIdKey);
                            noticeIdCtrl.text = '';
                            _noticeSheetIdNotifier.value = '';
                            if (!ctx.mounted) return;
                            showSelectedSnackbar(context, '공지 스프레드시트 설정을 초기화했습니다.');
                            setSheetState(() {});
                          },
                          icon: Icon(Icons.restore, color: t.destructive),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '공지 내용을 불러올 스프레드시트 ID를 입력하세요.\n'
                                  '스프레드시트 URL을 그대로 붙여넣어도 자동으로 ID를 추출합니다.\n',
                              style: text.bodyMedium?.copyWith(fontSize: 13, color: t.pageFg),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: noticeIdCtrl,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: '공지 스프레드시트 ID (또는 URL)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.grid_on_outlined),
                                helperText: '예) https://docs.google.com/spreadsheets/d/<ID>/edit',
                              ),
                              onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.check_circle_outline),
                                    onPressed: () async {
                                      final raw = noticeIdCtrl.text.trim();
                                      final id = SheetsConfig.extractSpreadsheetId(raw).trim();

                                      if (id.isEmpty) {
                                        if (!ctx.mounted) return;
                                        showFailedSnackbar(context, '스프레드시트 ID를 입력하세요.');
                                        return;
                                      }

                                      await prefs.setString(_kNoticeSpreadsheetIdKey, id);
                                      _noticeSheetIdNotifier.value = id;

                                      if (!ctx.mounted) return;
                                      showSuccessSnackbar(context, '공지 스프레드시트 ID를 저장했습니다.');
                                      setSheetState(() {});
                                    },
                                    label: const Text('저장'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.copy_all_outlined),
                                    onPressed: () async {
                                      final raw = '공지 Sheet ID: ${noticeIdCtrl.text.trim()}';
                                      await Clipboard.setData(ClipboardData(text: raw));
                                      if (!ctx.mounted) return;
                                      showSuccessSnackbar(context, '공지 스프레드시트 설정을 복사했습니다.');
                                    },
                                    label: const Text('설정 복사'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '저장 키: $_kNoticeSpreadsheetIdKey',
                              style: text.bodySmall?.copyWith(fontSize: 11, color: t.mutedFg),
                            ),
                          ],
                        ),
                      );
                    }

                    Widget buildGmailSection() {
                      return sectionBox(
                        icon: Icons.mail_outline,
                        title: '메일 전송 설정 (수신자만)',
                        trailing: IconButton(
                          tooltip: '기본값으로 초기화',
                          onPressed: () async {
                            await EmailConfig.clear();
                            final cfg = await EmailConfig.load();
                            mailToCtrl.text = cfg.to;
                            if (!ctx.mounted) return;
                            showSelectedSnackbar(context, '수신자를 기본값(빈 값)으로 복원했습니다.');
                          },
                          icon: Icon(Icons.restore, color: t.destructive),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: mailToCtrl,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: '수신자(To)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                                helperText: '쉼표로 여러 명 입력 가능 (예: a@x.com, b@y.com)',
                              ),
                              onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.check_circle_outline),
                                    onPressed: () async {
                                      final to = mailToCtrl.text.trim();
                                      if (!EmailConfig.isValidToList(to)) {
                                        if (!ctx.mounted) return;
                                        showFailedSnackbar(context, '수신자 이메일 형식을 확인해 주세요.');
                                        return;
                                      }
                                      await EmailConfig.save(EmailConfig(to: to));
                                      if (!ctx.mounted) return;
                                      showSuccessSnackbar(context, '수신자 설정을 저장했습니다.');
                                    },
                                    label: const Text('저장'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.copy_all_outlined),
                                    onPressed: () async {
                                      final raw = 'To: ${mailToCtrl.text}';
                                      await Clipboard.setData(ClipboardData(text: raw));
                                      if (!ctx.mounted) return;
                                      showSuccessSnackbar(context, '현재 수신자 설정을 복사했습니다.');
                                    },
                                    label: const Text('설정 복사'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '※ 저장되는 항목은 수신자(To)뿐입니다. 메일 제목·본문은 경위서 화면에서 작성합니다.',
                              style: text.bodySmall?.copyWith(fontSize: 12, color: t.mutedFg),
                            ),
                          ],
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      controller: sc,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 16,
                          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.tune_rounded),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '서비스 설정',
                                    style: text.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: t.pageFg,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '닫기',
                                  onPressed: () => Navigator.pop(ctx),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Divider(height: 1, color: t.border.withOpacity(.7)),
                            const SizedBox(height: 16),
                            buildOverlayPermissionSection(),
                            buildOverlayModeSection(),
                            buildCommuteTrueFalseToggleSection(),
                            buildRealtimeTabsToggleSection(),
                            buildNoticeSpreadsheetSection(),
                            buildGmailSection(),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _AnimatedSide(
          show: expanded,
          axisAlignment: -1.0,
          child: FilledButton.icon(
            onPressed: () => _openAppSettingsGate(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('앱 설정'),
          ),
        ),
        const SizedBox(width: 12),
        HeaderBadge(size: 64, ring: 3, onToggle: onToggle),
        const SizedBox(width: 12),
        _AnimatedSide(
          show: expanded,
          axisAlignment: 1.0,
          child: FilledButton.icon(
            onPressed: () async => _exitApp(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.power_settings_new),
            label: const Text('앱 종료'),
          ),
        ),
      ],
    );
  }
}

class _AnimatedSide extends StatelessWidget {
  const _AnimatedSide({
    required this.show,
    required this.child,
    this.axisAlignment = 0.0,
  });

  final bool show;
  final Widget child;
  final double axisAlignment;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) {
          return FadeTransition(
            opacity: anim,
            child: SizeTransition(
              axis: Axis.horizontal,
              sizeFactor: anim,
              axisAlignment: axisAlignment,
              child: ClipRect(child: child),
            ),
          );
        },
        child: show
            ? Container(
          key: const ValueKey('side-on'),
          alignment: Alignment.center,
          child: child,
        )
            : const SizedBox.shrink(key: ValueKey('side-off')),
      ),
    );
  }
}

class HeaderBadge extends StatelessWidget {
  const HeaderBadge({
    super.key,
    this.size = 64,
    this.ring = 3,
    this.onToggle,
  });

  final double size;
  final double ring;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final t = _HeaderTokens.of(context);

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: .92, end: 1),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.badgeRing,
          ),
          child: Padding(
            padding: EdgeInsets.all(ring),
            child: _HeaderBadgeInner(onToggle: onToggle),
          ),
        ),
      ),
    );
  }
}

class _HeaderBadgeInner extends StatefulWidget {
  const _HeaderBadgeInner({this.onToggle});

  final VoidCallback? onToggle;

  @override
  State<_HeaderBadgeInner> createState() => _HeaderBadgeInnerState();
}

class _HeaderBadgeInnerState extends State<_HeaderBadgeInner> with SingleTickerProviderStateMixin {
  late final AnimationController _rotCtrl;

  @override
  void initState() {
    super.initState();
    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _rotCtrl.forward(from: 0);
    widget.onToggle?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = _HeaderTokens.of(context);
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, cons) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: t.badgeInnerBg,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: t.badgeShadow,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onTap,
                  child: Center(
                    child: RotationTransition(
                      turns: Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _rotCtrl,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                      child: Icon(
                        Icons.dashboard_customize_rounded,
                        color: t.badgeIcon,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: cons.maxHeight * 0.12,
                left: cons.maxWidth * 0.22,
                right: cons.maxWidth * 0.22,
                child: IgnorePointer(
                  child: Container(
                    height: cons.maxHeight * 0.18,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
