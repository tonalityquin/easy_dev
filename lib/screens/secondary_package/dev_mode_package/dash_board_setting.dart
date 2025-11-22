// lib/screens/secondary_package/dev_mode_package/dash_board_setting.dart
//
// 최신 트렌드(UI/UX)로 깔끔하게 리팩터링 + '서비스 로그인' 팔레트 적용:
// - 상단 Large 스타일 헤더 느낌(섹션 배너) + 얇은 구분선
// - 토널 카드(tonal)와 라운딩, 여백 정리, 더 읽기 쉬운 섹션 타이틀
// - RefreshIndicator(끌어내려 새로고침) + 마지막 동기화 시각 뱃지
// - 스위치 토글, 액션 버튼 일관된 높이/패딩
// - 스프레드시트 ID 편집: 풀스크린 화이트 바텀시트 유지 + UX 개선
// - 스낵바는 snackbar_helper 사용
// - 잠금(LOCK) 시 시각적 오버레이, 입력 차단 유지
// - 토글 연타 방지, 비동기 예외 처리 보강
//
// 동작적으로는 기존과 동일하며, 레이아웃/스타일만 개선되었습니다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../states/area/area_state.dart';
import '../../../states/location/location_state.dart';
import '../../../states/bill/bill_state.dart';
import '../../../utils/tts/tts_user_filters.dart';
import '../../../utils/api/sheets_config.dart';
import '../../../utils/tts/chat_tts_listener_service.dart';
import '../../../utils/tts/plate_tts_listener_service.dart'; // ✅ PlateTTS setEnabled / updateFilters
import '../../../utils/snackbar_helper.dart';
import '../../../utils/init/logout_helper.dart';

/// 서비스 로그인 카드 팔레트 (일관된 브랜드 톤 적용)
class _SvcColors {
  static const base = Color(0xFF0D47A1); // primary (버튼/강조)
  static const dark = Color(0xFF09367D); // 텍스트 강조/보더
  static const light = Color(0xFF5472D3); // 톤 다운 surface
  static const fg = Color(0xFFFFFFFF); // 포그라운드
}

/// 대시보드 설정: 이 페이지에서 TTS 알림 및 각종 제어를 직접 조절합니다.
/// 잠금 스위치가 켜진 상태(true)면 본문 조작이 차단됩니다.
class DashboardSetting extends StatefulWidget {
  const DashboardSetting({super.key});

  @override
  State<DashboardSetting> createState() => _DashboardSettingState();
}

class _DashboardSettingState extends State<DashboardSetting> {
  static const _prefsLockedKey = 'dashboard_setting_locked';

  TtsUserFilters _filters = TtsUserFilters.defaults();
  bool _loading = true;

  // TTS 적용 중(토글 연타 방지용)
  bool _applying = false;

  // 새로고침 로딩 상태
  bool _refreshing = false;

  // 업로드용 스프레드시트 ID 표시/관리용 상태 (출퇴근)
  String? _commuteSheetId;

  // ✅ 업무 종료 보고용 스프레드시트 ID 표시/관리용 상태 (신규)
  String? _endReportSheetId;

  // 화면 잠금(기본값 true)
  bool _locked = true;

  // 마지막 새로고침 시각
  DateTime? _lastRefreshAt;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadLockState(), _load()]);
  }

  Future<void> _loadLockState() async {
    final prefs = await SharedPreferences.getInstance();
    final locked = prefs.getBool(_prefsLockedKey);
    if (mounted) {
      setState(() => _locked = locked ?? true);
    }
  }

  Future<void> _saveLockState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLockedKey, value);
  }

  Future<void> _load() async {
    final loaded = await TtsUserFilters.load();
    final sheetId = await SheetsConfig.getCommuteSheetId();
    final endSheetId = await SheetsConfig.getEndReportSheetId(); // ⬅️ 추가

    // 시작 시 Chat TTS on/off도 즉시 반영
    try {
      await ChatTtsListenerService.setEnabled(loaded.chat);
    } catch (e) {
      debugPrint('ChatTtsListenerService.setEnabled 초기화 실패: $e');
    }

    // ✅ PlateTTS: parking/departure/completed 중 하나라도 켜져 있으면 전체 활성화
    try {
      final masterOn = loaded.parking || loaded.departure || loaded.completed;
      await PlateTtsListenerService.setEnabled(masterOn);
      // ✅ 앱 isolate에서도 즉시 반영(중요): 타입별 필터 상태를 직접 주입
      PlateTtsListenerService.updateFilters(loaded);
    } catch (e) {
      debugPrint('PlateTtsListenerService 초기화 실패: $e');
    }

    // ✅ FG isolate에도 동기화: 필터 & area 전달(필요 시)
    try {
      final area = context.read<AreaState>().currentArea;
      FlutterForegroundTask.sendDataToTask({
        'area': area,
        'ttsFilters': loaded.toMap(),
      });
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _filters = loaded;
      _commuteSheetId = sheetId;
      _endReportSheetId = endSheetId; // ⬅️ 추가
      _loading = false;
    });
  }

  Future<void> _apply(TtsUserFilters next) async {
    if (_applying) return;
    setState(() {
      _filters = next;
      _applying = true;
    });

    try {
      await _filters.save();

      // Chat TTS on/off 즉시 반영
      await ChatTtsListenerService.setEnabled(_filters.chat);

      // ✅ PlateTTS: parking/departure/completed 합성하여 마스터 on/off 즉시 반영
      final masterOn = _filters.parking || _filters.departure || _filters.completed;
      await PlateTtsListenerService.setEnabled(masterOn);

      // ✅ 앱 isolate 필터 즉시 반영(핵심)
      PlateTtsListenerService.updateFilters(_filters);

      // ✅ FG isolate에도 최신 필터 전달
      final area = context.read<AreaState>().currentArea; // 비어있을 수도 있음
      FlutterForegroundTask.sendDataToTask({
        'area': area,
        'ttsFilters': _filters.toMap(),
      });

      if (mounted) {
        showSuccessSnackbar(context, 'TTS 설정이 적용되었습니다.');
      }
    } catch (e) {
      debugPrint('TTS 적용 실패: $e');
      if (mounted) {
        showFailedSnackbar(context, '적용 실패: $e');
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _resendToForeground() async {
    final area = context.read<AreaState>().currentArea;
    // ✅ 재전송 시에도 앱 isolate 필터 싱크를 보수적으로 맞춰줌
    PlateTtsListenerService.updateFilters(_filters);
    FlutterForegroundTask.sendDataToTask({
      'area': area,
      'ttsFilters': _filters.toMap(),
    });
    if (mounted) {
      showSuccessSnackbar(context, '현재 TTS 설정을 포그라운드 서비스에 재전송했습니다.');
    }
  }

  // 주차 구역/정산 수동 새로고침
  Future<void> _manualRefreshAll() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final locationState = context.read<LocationState>();
      final billState = context.read<BillState>();

      await locationState.manualLocationRefresh();
      await billState.manualBillRefresh();

      if (mounted) {
        setState(() => _lastRefreshAt = DateTime.now());
        showSuccessSnackbar(context, '데이터를 새로고침했습니다.');
      }
    } catch (e) {
      debugPrint('수동 새로고침 실패: $e');
      if (mounted) {
        showFailedSnackbar(context, '새로고침 실패: $e');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // 로그아웃
  Future<void> _logout() async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(seconds: 1),
      // 목적지 미지정 → 기본(허브 선택)으로 이동
    );
  }

  // 스프레드시트 ID/URL 삽입(변경) 바텀시트 - 풀스크린 흰 배경/키보드 패딩 (출퇴근용)
  Future<void> _openSetCommuteSheetIdSheet() async {
    final current = await SheetsConfig.getCommuteSheetId();
    final textCtrl = TextEditingController(text: current ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true, // 상단 안전영역
      backgroundColor: Colors.white, // 전면 흰 배경
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 1.0, // 최상단까지
          maxChildSize: 1.0,
          minChildSize: 0.4,
          builder: (ctx, sc) => SingleChildScrollView(
            controller: sc,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, // 키보드 패딩
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.assignment_outlined, color: _SvcColors.dark),
                      const SizedBox(width: 8),
                      const Text(
                        '업로드용 Google Sheets',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textCtrl,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '스프레드시트 ID 또는 URL (붙여넣기 가능)',
                      helperText: 'URL 전체를 붙여넣어도 ID만 자동 추출됩니다.',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link_rounded, color: _SvcColors.dark),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _SvcColors.base, width: 1.2),
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                    onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.copy_rounded, color: _SvcColors.dark),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _SvcColors.light.withOpacity(.45)),
                          ),
                          onPressed: () async {
                            final raw = textCtrl.text.trim();
                            if (raw.isEmpty) return;
                            await Clipboard.setData(ClipboardData(text: raw));
                            if (!mounted) return;
                            showSuccessSnackbar(context, '입력값을 복사했습니다.');
                          },
                          label: const Text('복사', style: TextStyle(color: _SvcColors.dark)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _SvcColors.base,
                            foregroundColor: _SvcColors.fg,
                          ),
                          onPressed: () async {
                            final raw = textCtrl.text.trim();
                            if (raw.isEmpty) return;
                            final id = SheetsConfig.extractSpreadsheetId(raw);
                            await SheetsConfig.setCommuteSheetId(id);
                            if (!mounted) return;
                            setState(() => _commuteSheetId = id);
                            Navigator.pop(ctx);
                            showSuccessSnackbar(context, '업로드용 스프레드시트 ID가 저장되었습니다.');
                          },
                          label: const Text('저장'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 스프레드시트 ID 초기화 (출퇴근용)
  Future<void> _clearCommuteSheetId() async {
    await SheetsConfig.clearCommuteSheetId();
    if (!mounted) return;
    setState(() => _commuteSheetId = null);
    showSelectedSnackbar(context, '업로드용 스프레드시트 ID를 초기화했습니다.');
  }

  // 스프레드시트 ID/URL 삽입(변경) 바텀시트 (업무 종료 보고용)
  Future<void> _openSetEndReportSheetIdSheet() async {
    final current = await SheetsConfig.getEndReportSheetId();
    final textCtrl = TextEditingController(text: current ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 1.0,
          maxChildSize: 1.0,
          minChildSize: 0.4,
          builder: (ctx, sc) => SingleChildScrollView(
            controller: sc,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.assignment_turned_in_outlined, color: _SvcColors.dark),
                      const SizedBox(width: 8),
                      const Text(
                        '업무 종료 보고용 Google Sheets',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textCtrl,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '스프레드시트 ID 또는 URL (붙여넣기 가능)',
                      helperText: 'URL 전체를 붙여넣어도 ID만 자동 추출됩니다.',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link_rounded, color: _SvcColors.dark),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _SvcColors.base, width: 1.2),
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                    onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.copy_rounded, color: _SvcColors.dark),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _SvcColors.light.withOpacity(.45)),
                          ),
                          onPressed: () async {
                            final raw = textCtrl.text.trim();
                            if (raw.isEmpty) return;
                            await Clipboard.setData(ClipboardData(text: raw));
                            if (!mounted) return;
                            showSuccessSnackbar(context, '입력값을 복사했습니다.');
                          },
                          label: const Text('복사', style: TextStyle(color: _SvcColors.dark)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _SvcColors.base,
                            foregroundColor: _SvcColors.fg,
                          ),
                          onPressed: () async {
                            final raw = textCtrl.text.trim();
                            if (raw.isEmpty) return;
                            final id = SheetsConfig.extractSpreadsheetId(raw);
                            await SheetsConfig.setEndReportSheetId(id);
                            if (!mounted) return;
                            setState(() => _endReportSheetId = id);
                            Navigator.pop(ctx);
                            showSuccessSnackbar(context, '업무 종료 보고 스프레드시트 ID가 저장되었습니다.');
                          },
                          label: const Text('저장'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 스프레드시트 ID 초기화 (업무 종료 보고용)
  Future<void> _clearEndReportSheetId() async {
    await SheetsConfig.clearEndReportSheetId();
    if (!mounted) return;
    setState(() => _endReportSheetId = null);
    showSelectedSnackbar(context, '업무 종료 보고 스프레드시트 ID를 초기화했습니다.');
  }

  String _formatLastSync(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = dt.toLocal();
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  // ⬇️ 좌측 상단(11시) 고정 라벨: 'controller'
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

    return SafeArea(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: Setting',
              child: Text('Setting', style: style),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.select<AreaState, String>((s) => s.currentArea);

    final bodyList = <Widget>[
      const _HeaderBanner(),
      const SizedBox(height: 12),

      // 안내 카드(지역 비어있음)
      if ((currentArea).isEmpty)
        _Section(
          title: '지역 설정 필요',
          icon: Icons.info_outline,
          tone: _Tone.warning,
          child: const Text(
            '현재 지역 정보가 비어 있습니다. FG 서비스에서 지역 기반 구독을 사용하는 경우, '
                '지역 설정 완료 후 다시 적용하세요.',
          ),
        ),

      // TTS 설정
      _Section(
        title: 'TTS 알림 설정',
        icon: Icons.record_voice_over_rounded,
        subtitle: '스위치를 변경하면 즉시 저장되고 FG 서비스에 적용됩니다.',
        trailing: _applying
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : null,
        child: Column(
          children: [
            _SwitchTile(
              title: '채팅 읽어주기',
              subtitle: '구역 채팅 최신 메시지를 음성으로 읽어줍니다',
              value: _filters.chat,
              onChanged: _applying ? null : (v) => _apply(_filters.copyWith(chat: v)),
              icon: Icons.chat_bubble_outline_rounded,
            ),
            const Divider(height: 1),
            _SwitchTile(
              title: '입차 요청',
              value: _filters.parking,
              onChanged: _applying ? null : (v) => _apply(_filters.copyWith(parking: v)),
              icon: Icons.local_parking_rounded,
            ),
            const Divider(height: 1),
            _SwitchTile(
              title: '출차 요청',
              value: _filters.departure,
              onChanged: _applying ? null : (v) => _apply(_filters.copyWith(departure: v)),
              icon: Icons.exit_to_app_rounded,
            ),
            const Divider(height: 1),
            _SwitchTile(
              title: '출차 완료(2회)',
              value: _filters.completed,
              onChanged: _applying ? null : (v) => _apply(_filters.copyWith(completed: v)),
              icon: Icons.done_all_rounded,
            ),
          ],
        ),
      ),

      // 현재 지역
      _Section(
        title: '현재 지역',
        icon: Icons.place_outlined,
        child: Row(
          children: [
            Expanded(
              child: Text(
                currentArea.isEmpty ? '(미설정)' : currentArea,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: _SvcColors.light.withOpacity(.20),
                foregroundColor: _SvcColors.dark,
              ),
              onPressed: _loading ? null : _resendToForeground,
              icon: const Icon(Icons.send),
              label: const Text('재적용'),
            ),
          ],
        ),
      ),

      // 업로드용 스프레드시트 (출퇴근)
      _Section(
        title: '업로드 스프레드시트(ID)',
        icon: Icons.assignment_outlined,
        subtitle: 'URL 전체를 붙여넣어도 ID만 자동 추출됩니다.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow(
              label: '현재',
              value: (_commuteSheetId == null || _commuteSheetId!.isEmpty) ? '(미설정)' : _commuteSheetId!,
              valueStyle: const TextStyle(fontWeight: FontWeight.w700),
              actions: [
                IconButton(
                  tooltip: '복사',
                  onPressed: (_commuteSheetId == null || _commuteSheetId!.isEmpty)
                      ? null
                      : () async {
                    await Clipboard.setData(ClipboardData(text: _commuteSheetId!));
                    if (!mounted) return;
                    showSuccessSnackbar(context, '스프레드시트 ID를 복사했습니다.');
                  },
                  icon: const Icon(Icons.copy_rounded, color: _SvcColors.dark),
                ),
                IconButton(
                  tooltip: '초기화',
                  onPressed:
                  (_commuteSheetId == null || _commuteSheetId!.isEmpty) ? null : _clearCommuteSheetId,
                  icon: const Icon(Icons.delete_outline_rounded, color: _SvcColors.dark),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openSetCommuteSheetIdSheet,
                    icon: const Icon(Icons.link),
                    label: const Text('ID/URL 삽입 또는 변경'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _SvcColors.base,
                      foregroundColor: _SvcColors.fg,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      // ===================== 신규 섹션: 업무 종료 보고 시트 =====================
      _Section(
        title: '업무 종료 보고 스프레드시트(ID)',
        icon: Icons.assignment_turned_in_outlined,
        subtitle: 'URL 전체를 붙여넣어도 ID만 자동 추출됩니다.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow(
              label: '현재',
              value: (_endReportSheetId == null || _endReportSheetId!.isEmpty)
                  ? '(미설정)'
                  : _endReportSheetId!,
              valueStyle: const TextStyle(fontWeight: FontWeight.w700),
              actions: [
                IconButton(
                  tooltip: '복사',
                  onPressed: (_endReportSheetId == null || _endReportSheetId!.isEmpty)
                      ? null
                      : () async {
                    await Clipboard.setData(ClipboardData(text: _endReportSheetId!));
                    if (!mounted) return;
                    showSuccessSnackbar(context, '스프레드시트 ID를 복사했습니다.');
                  },
                  icon: const Icon(Icons.copy_rounded, color: _SvcColors.dark),
                ),
                IconButton(
                  tooltip: '초기화',
                  onPressed:
                  (_endReportSheetId == null || _endReportSheetId!.isEmpty) ? null : _clearEndReportSheetId,
                  icon: const Icon(Icons.delete_outline_rounded, color: _SvcColors.dark),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openSetEndReportSheetIdSheet,
                    icon: const Icon(Icons.link),
                    label: const Text('ID/URL 삽입 또는 변경'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _SvcColors.base,
                      foregroundColor: _SvcColors.fg,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      // 데이터 새로고침
      _Section(
        title: '데이터 새로고침',
        icon: Icons.refresh_rounded,
        subtitle: '주차 구역/정산 데이터를 수동으로 동기화합니다.',
        trailing: _refreshing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : (_lastRefreshAt != null
            ? _Pill(text: '마지막: ${_formatLastSync(_lastRefreshAt!)}')
            : null),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loading || _refreshing ? null : _manualRefreshAll,
                icon: _refreshing
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_SvcColors.fg),
                  ),
                )
                    : const Icon(Icons.sync),
                label: const Text('지금 새로고침'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _SvcColors.base,
                  foregroundColor: _SvcColors.fg,
                ),
              ),
            ),
          ],
        ),
      ),

      // 로그아웃
      _Section(
        title: '로그아웃',
        icon: Icons.logout_rounded,
        tone: _Tone.danger,
        subtitle: '포그라운드 서비스를 중지하고 로그인 화면(허브 선택 경유)으로 이동합니다.',
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _logout,
                icon: const Icon(Icons.logout, color: Colors.black87),
                label: const Text('로그아웃', style: TextStyle(color: Colors.black87)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.black.withOpacity(.22)),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ];

    final listView = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
      onRefresh: _manualRefreshAll,
      edgeOffset: 80,
      color: _SvcColors.base,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: bodyList,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '대시보드 설정',
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        // ⬇️ 11시 라벨을 AppBar 영역에 고정
        flexibleSpace: _buildScreenTag(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Icon(_locked ? Icons.lock : Icons.lock_open, color: _SvcColors.dark),
                Switch.adaptive(
                  activeColor: _SvcColors.base,
                  value: _locked, // true면 잠금
                  onChanged: (v) async {
                    setState(() => _locked = v);
                    await _saveLockState(v);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 잠금 시 입력 차단
          IgnorePointer(ignoring: _locked, child: listView),

          // 잠금 상태 시 시각적 오버레이
          if (_locked)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.6),
                child: const Center(child: _LockedBanner()),
              ),
            ),
        ],
      ),
    );
  }
}

/// =======================
/// 디자인 보조 위젯들
/// =======================

enum _Tone { normal, warning, danger }

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
    this.tone = _Tone.normal,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg = switch (tone) {
      _Tone.normal => cs.surface,
      _Tone.warning => const Color(0xFFFFF8E1),
      _Tone.danger => const Color(0xFFFFEBEE),
    };
    final Color border = switch (tone) {
      _Tone.normal => _SvcColors.light.withOpacity(.35),
      _Tone.warning => const Color(0xFFFFECB3),
      _Tone.danger => const Color(0xFFFFCDD2),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              icon: icon,
              title: title,
              subtitle: subtitle,
              trailing: trailing,
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _SvcColors.light.withOpacity(0.20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(iconDataPlaceholder, size: 20), // placeholder replaced below
        ).withIcon(icon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _SvcColors.dark,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text(
                    subtitle!,
                    style: text.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 작은 헬퍼: 위젯의 아이콘을 교체하기 위한 확장 (위에서 Container에 아이콘 주입)
extension _WithIcon on Widget {
  Widget withIcon(IconData icon) {
    return Stack(
      children: [
        this,
        Positioned.fill(
          child: Center(
            child: Icon(icon, size: 20, color: _SvcColors.dark),
          ),
        ),
      ],
    );
  }
}

// 더미 상수(컴파일 편의) — _SectionHeader에서 withIcon으로 즉시 대체됨
const IconData iconDataPlaceholder = Icons.circle;

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: icon == null
          ? null
          : Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _SvcColors.light.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: _SvcColors.dark),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, color: _SvcColors.dark),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 12)),
      trailing: Switch.adaptive(
        value: value,
        activeColor: _SvcColors.base,
        onChanged: onChanged,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueStyle,
    this.actions,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: text.bodySmall?.copyWith(color: Colors.black54)),
        const SizedBox(width: 10),
        Expanded(child: Text(value, style: valueStyle)),
        if (actions != null) ...actions!,
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _SvcColors.light.withOpacity(.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _SvcColors.light.withOpacity(.35)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _SvcColors.dark,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _SvcColors.light.withOpacity(.95),
            _SvcColors.base.withOpacity(.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _SvcColors.dark.withOpacity(.18)),
      ),
      child: Row(
        children: const [
          Icon(Icons.tune_rounded, color: _SvcColors.fg),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '앱 동작과 알림을 여기서 관리하세요.\n변경 즉시 기기에 적용됩니다.',
              style: TextStyle(
                color: _SvcColors.fg,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.lock, size: 48, color: Colors.black54),
        SizedBox(height: 8),
        Text(
          '화면이 잠금 상태입니다',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4),
        Text('오른쪽 상단 스위치를 끄면 조작할 수 있어요'),
      ],
    );
  }
}
