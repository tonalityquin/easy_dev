// lib/screens/secondary_package/office_mode_package/dashboard_setting.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../states/area/area_state.dart';
import '../../../states/location/location_state.dart';
import '../../../states/bill/bill_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/blocking_dialog.dart';
import '../../../utils/tts/tts_user_filters.dart';
import '../../../utils/sheets_config.dart';

/// 대시보드 설정: 이 페이지에서 TTS 알림 및 각종 제어를 직접 조절합니다.
/// 잠금 스위치가 켜진 상태(true)면 본문 조작이 차단됩니다.
class DashboardSetting extends StatefulWidget {
  const DashboardSetting({super.key});

  @override
  State<DashboardSetting> createState() => _DashboardSettingState();
}

class _DashboardSettingState extends State<DashboardSetting> {
  TtsUserFilters _filters = TtsUserFilters.defaults();
  bool _loading = true;

  // 새로고침 로딩 상태
  bool _refreshing = false;

  // ⬇️ 업로드용 스프레드시트 ID 표시/관리용 상태
  String? _commuteSheetId;

  // ✅ 화면 잠금(기본값 true)
  bool _locked = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await TtsUserFilters.load();
    final sheetId = await SheetsConfig.getCommuteSheetId();
    if (!mounted) return;
    setState(() {
      _filters = loaded;
      _commuteSheetId = sheetId;
      _loading = false;
    });
  }

  Future<void> _apply(TtsUserFilters next) async {
    setState(() => _filters = next);
    await _filters.save();

    final area = context.read<AreaState>().currentArea; // 비어있을 수도 있음
    FlutterForegroundTask.sendDataToTask({
      'area': area,
      'ttsFilters': _filters.toMap(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TTS 설정이 적용되었습니다.')),
      );
    }
  }
  Future<void> _resendToForeground() async {
    final area = context.read<AreaState>().currentArea;
    FlutterForegroundTask.sendDataToTask({
      'area': area,
      'ttsFilters': _filters.toMap(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 TTS 설정을 포그라운드 서비스에 재전송했습니다.')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('데이터를 새로고침했습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('새로고침 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // ⬇️ 로그아웃
  Future<void> _logout() async {
    try {
      await runWithBlockingDialog(
        context: context,
        message: '로그아웃 중입니다...',
        task: () async {
          final userState = context.read<UserState>();
          await FlutterForegroundTask.stopService();
          await Future.delayed(const Duration(seconds: 1));
          await userState.clearUserToPhone();
        },
      );

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그아웃 실패: $e')),
        );
      }
    }
  }

  // ⬇️ 스프레드시트 ID/URL 삽입(변경) 바텀시트
  Future<void> _openSetCommuteSheetIdSheet() async {
    final current = await SheetsConfig.getCommuteSheetId();
    final textCtrl = TextEditingController(text: current ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('업로드용 Google Sheets ID 또는 전체 URL',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                decoration: const InputDecoration(
                  labelText: '스프레드시트 ID 또는 URL (붙여넣기 가능)',
                  helperText: 'URL 전체를 붙여넣어도 ID만 자동 추출됩니다.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                onPressed: () async {
                  final raw = textCtrl.text.trim();
                  if (raw.isEmpty) return;
                  final id = SheetsConfig.extractSpreadsheetId(raw);
                  await SheetsConfig.setCommuteSheetId(id);
                  if (!mounted) return;
                  setState(() => _commuteSheetId = id);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('업로드용 스프레드시트 ID가 저장되었습니다.')),
                  );
                },
                label: const Text('저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⬇️ 스프레드시트 ID 초기화
  Future<void> _clearCommuteSheetId() async {
    await SheetsConfig.clearCommuteSheetId();
    if (!mounted) return;
    setState(() => _commuteSheetId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('업로드용 스프레드시트 ID를 초기화했습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.select<AreaState, String>((s) => s.currentArea);

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if ((currentArea).isEmpty)
          Card(
            color: const Color(0xFFFFF8E1),
            margin: const EdgeInsets.only(bottom: 12),
            child: const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(
                '현재 지역 정보가 비어 있습니다. FG 서비스에서 지역 기반 구독을 사용하는 경우, '
                    '지역 설정 완료 후 다시 적용하세요.',
              ),
            ),
          ),

        // TTS 설정 카드
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const ListTile(
                title: Text('TTS 알림 설정',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('스위치를 변경하면 즉시 저장되고 FG 서비스에 적용됩니다.'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('입차 요청'),
                value: _filters.parking,
                onChanged: (v) => _apply(_filters.copyWith(parking: v)),
              ),
              SwitchListTile(
                title: const Text('출차 요청'),
                value: _filters.departure,
                onChanged: (v) =>
                    _apply(_filters.copyWith(departure: v)),
              ),
              SwitchListTile(
                title: const Text('출차 완료(2회)'),
                value: _filters.completed,
                onChanged: (v) =>
                    _apply(_filters.copyWith(completed: v)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 현재 지역 카드
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('현재 지역'),
            subtitle: Text(
              currentArea.isEmpty ? '(미설정)' : currentArea,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: IconButton(
              tooltip: '현재 설정 재적용',
              icon: const Icon(Icons.send),
              onPressed: _loading ? null : _resendToForeground,
            ),
          ),
        ),

        const Divider(height: 24, thickness: 1),

        // 업로드용 스프레드시트 ID 카드
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.assignment_outlined),
                  title: const Text(
                    '업로드 스프레드시트(ID)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _commuteSheetId == null || _commuteSheetId!.isEmpty
                        ? '(미설정)'
                        : _commuteSheetId!,
                  ),
                  trailing: IconButton(
                    tooltip: 'ID/URL 삽입 또는 변경',
                    icon: const Icon(Icons.edit),
                    onPressed: _openSetCommuteSheetIdSheet,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _openSetCommuteSheetIdSheet,
                        icon: const Icon(Icons.link),
                        label: const Text('ID/URL 삽입 또는 변경'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_commuteSheetId == null ||
                            _commuteSheetId!.isEmpty)
                            ? null
                            : _clearCommuteSheetId,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('초기화'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 데이터 새로고침 카드
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh),
                  title: Text(
                    '데이터 새로고침',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('주차 구역/정산 데이터를 수동으로 동기화합니다.'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed:
                  _loading || _refreshing ? null : _manualRefreshAll,
                  icon: _refreshing
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white),
                    ),
                  )
                      : const Icon(Icons.sync),
                  label: const Text('지금 새로고침'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 로그아웃 카드
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text(
                    '로그아웃',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle:
                  Text('포그라운드 서비스를 중지하고 로그인 화면으로 이동합니다.'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('로그아웃'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Color(0xFFBDBDBD)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '대시보드 설정',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Icon(_locked ? Icons.lock : Icons.lock_open),
                Switch.adaptive(
                  value: _locked, // true면 잠금
                  onChanged: (v) => setState(() => _locked = v),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ✅ 잠금 시 입력 차단
          IgnorePointer(ignoring: _locked, child: body),

          // ✅ 잠금 상태 시 시각적 오버레이
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
