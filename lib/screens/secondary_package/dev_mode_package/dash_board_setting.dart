import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../states/area/area_state.dart';
import '../../../states/location/location_state.dart';
import '../../../states/bill/bill_state.dart';
import '../../../states/user/user_state.dart';           // ⬅️ 추가
import '../../../utils/blocking_dialog.dart';           // ⬅️ 추가
import '../../../utils/tts/tts_user_filters.dart';

/// 대시보드 설정: 이 페이지에서 TTS 알림 및 각종 제어를 직접 조절합니다.
/// - 스위치 변경 즉시: 저장 -> 포그라운드 서비스로 전달 -> 스낵바 안내
/// - 기본값 복원 / 현재 설정 재적용 / 데이터 새로고침 / 로그아웃 제공
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await TtsUserFilters.load();
    if (!mounted) return;
    setState(() {
      _filters = loaded;
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

  Future<void> _resetToDefaults() async {
    await _apply(TtsUserFilters.defaults());
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

  // ⬇️ 추가: 로그아웃(컨트롤러의 logout 로직 포팅)
  Future<void> _logout() async {
    try {
      await runWithBlockingDialog(
        context: context,
        message: '로그아웃 중입니다...',
        task: () async {
          final userState = context.read<UserState>();
          await FlutterForegroundTask.stopService();
          await userState.isHeWorking();
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

  @override
  Widget build(BuildContext context) {
    final currentArea = context.select<AreaState, String>((s) => s.currentArea);

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
          IconButton(
            tooltip: '기본값 복원',
            icon: const Icon(Icons.restore),
            onPressed: _loading ? null : _resetToDefaults,
          ),
          IconButton(
            tooltip: '현재 설정 재적용',
            icon: const Icon(Icons.sync),
            onPressed: _loading ? null : _resendToForeground,
          ),
        ],
      ),
      body: _loading
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
                  title: Text('TTS 알림 설정', style: TextStyle(fontWeight: FontWeight.w700)),
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
                  onChanged: (v) => _apply(_filters.copyWith(departure: v)),
                ),
                SwitchListTile(
                  title: const Text('출차 완료(2회)'),
                  value: _filters.completed,
                  onChanged: (v) => _apply(_filters.copyWith(completed: v)),
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

          // 데이터 새로고침 카드
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFE0E0E0)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    onPressed: _loading || _refreshing ? null : _manualRefreshAll,
                    icon: _refreshing
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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

          // ⬇️ 새로 추가: 로그아웃 카드
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFE0E0E0)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    subtitle: Text('포그라운드 서비스를 중지하고 로그인 화면으로 이동합니다.'),
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
      ),
    );
  }
}
