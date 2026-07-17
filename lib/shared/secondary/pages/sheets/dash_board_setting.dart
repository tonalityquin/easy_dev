import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/init/logout_helper.dart';
import '../../../../app/utils/operational_data_sync_workflow.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../secondary/widgets/ops_console_widgets.dart';
import '../../../tts/application/tts_sync_helper.dart';
import '../../../tts/application/tts_user_filters.dart';

class DashboardSetting extends StatefulWidget {
  const DashboardSetting({super.key});

  @override
  State<DashboardSetting> createState() => _DashboardSettingState();
}

class _DashboardSettingState extends State<DashboardSetting> {
  static const _prefsLockedKey = 'dashboard_setting_locked';

  TtsUserFilters _filters = TtsUserFilters.defaults();
  bool _loading = true;
  bool _applying = false;
  bool _refreshing = false;
  bool _locked = true;
  bool? _hasMonthlyParking;
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
    if (!mounted) return;
    setState(() => _locked = locked ?? true);
  }

  Future<void> _saveLockState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLockedKey, value);
  }

  Future<void> _load() async {
    final loaded = await TtsUserFilters.load();
    final prefs = await SharedPreferences.getInstance();
    final hasMonthlyParking = prefs.getBool(
      OperationalDataSyncWorkflow.monthlyParkingKey,
    );
    final lastRefreshAt = DateTime.tryParse(
      prefs.getString(OperationalDataSyncWorkflow.lastSyncAtKey) ?? '',
    );

    try {
      await TtsSyncHelper.apply(
        context,
        loaded,
        save: false,
        showSnackbar: false,
      );
    } catch (e) {
      debugPrint('TTS 초기 동기화 실패: $e');
    }

    if (!mounted) return;
    setState(() {
      _filters = loaded;
      _hasMonthlyParking = hasMonthlyParking;
      _lastRefreshAt = lastRefreshAt;
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
      await TtsSyncHelper.apply(
        context,
        next,
        save: true,
        showSnackbar: false,
      );
    } catch (e) {
      debugPrint('TTS 적용 실패: $e');
    } finally {
      if (!mounted) return;
      setState(() => _applying = false);
    }
  }

  Future<void> _resendToForeground() async {
    try {
      await TtsSyncHelper.apply(
        context,
        _filters,
        save: false,
        showSnackbar: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 설정을 포그라운드 서비스에 재적용했습니다.')),
      );
    } catch (e) {
      debugPrint('FG 재전송 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('포그라운드 서비스 재적용에 실패했습니다.')),
      );
    }
  }

  Future<void> _manualRefreshAll() async {
    if (_refreshing) return;

    setState(() => _refreshing = true);
    try {
      await OperationalDataSyncWorkflow.run(context: context);
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(seconds: 1),
    );
  }

  Future<void> _toggleLock() async {
    final next = !_locked;
    setState(() => _locked = next);
    await _saveLockState(next);
  }

  String _formatLastSync(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = dt.toLocal();
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  int get _enabledTtsCount {
    var count = 0;
    if (_filters.parking) count++;
    if (_filters.departure) count++;
    if (_filters.completed) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentArea = context.select<AreaState, String>((s) => s.currentArea.trim());
    final areaLabel = currentArea.isEmpty ? '지역 미설정' : currentArea;
    final monthlyLabel = _hasMonthlyParking == null ? '대기' : (_hasMonthlyParking! ? '있음' : '없음');

    return OpsConsoleScaffold(
      title: '대시보드 설정',
      icon: Icons.dashboard_customize_rounded,
      areaLabel: areaLabel,
      loading: _loading,
      trailing: IconButton.filledTonal(
        tooltip: _locked ? '잠금 해제' : '잠금',
        onPressed: _loading ? null : _toggleLock,
        icon: Icon(_locked ? Icons.lock_rounded : Icons.lock_open_rounded),
      ),
      metrics: [
        OpsMetric(label: 'TTS ON', value: '$_enabledTtsCount/3', icon: Icons.record_voice_over_rounded, color: cs.primary),
        OpsMetric(label: '잠금', value: _locked ? 'ON' : 'OFF', icon: _locked ? Icons.lock_rounded : Icons.lock_open_rounded, color: _locked ? cs.error : cs.primary),
        OpsMetric(label: '월정기', value: monthlyLabel, icon: Icons.local_parking_rounded, color: _hasMonthlyParking == true ? cs.primary : cs.onInverseSurface),
        OpsMetric(label: '새로고침', value: _lastRefreshAt == null ? '-' : _formatLastSync(_lastRefreshAt!).substring(11), icon: Icons.sync_rounded, color: cs.primary),
      ],
      body: _loading
          ? const SizedBox.shrink()
          : Stack(
              children: [
                AbsorbPointer(
                  absorbing: _locked,
                  child: RefreshIndicator(
                    onRefresh: _manualRefreshAll,
                    color: cs.primary,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      children: [
                        if (currentArea.isEmpty) ...[
                          OpsPanel(
                            accentColor: cs.error,
                            child: const OpsSectionTitle(
                              title: '지역 설정 필요',
                              subtitle: '지역 기반 구독과 데이터 동기화를 사용하려면 현재 지역을 먼저 설정하세요.',
                              icon: Icons.info_outline_rounded,
                            ),
                          ),
                        ],
                        OpsPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OpsSectionTitle(
                                title: 'TTS 알림 채널',
                                subtitle: '변경 즉시 저장되고 포그라운드 서비스로 동기화됩니다.',
                                icon: Icons.campaign_rounded,
                                trailing: _applying
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                      )
                                    : OpsStatusBadge(label: '$_enabledTtsCount개 활성', color: cs.primary),
                              ),
                              const SizedBox(height: 12),
                              _SwitchTile(
                                title: '입차 요청',
                                subtitle: '입차 요청 발생 시 음성 안내',
                                value: _filters.parking,
                                onChanged: _applying ? null : (v) => _apply(_filters.copyWith(parking: v)),
                                icon: Icons.local_parking_rounded,
                              ),
                              const OpsDivider(),
                              _SwitchTile(
                                title: '출차 요청',
                                subtitle: '출차 요청 발생 시 음성 안내',
                                value: _filters.departure,
                                onChanged: _applying ? null : (v) => _apply(_filters.copyWith(departure: v)),
                                icon: Icons.exit_to_app_rounded,
                              ),
                              const OpsDivider(),
                              _SwitchTile(
                                title: '출차 완료 2회',
                                subtitle: '출차 완료 발생 시 반복 안내',
                                value: _filters.completed,
                                onChanged: _applying ? null : (v) => _apply(_filters.copyWith(completed: v)),
                                icon: Icons.done_all_rounded,
                              ),
                            ],
                          ),
                        ),
                        OpsPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OpsSectionTitle(
                                title: '현재 운영 지점',
                                subtitle: currentArea.isEmpty ? '지역 값이 비어 있습니다.' : '$currentArea 기준으로 구독과 캐시를 맞춥니다.',
                                icon: Icons.place_outlined,
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(child: OpsInfoPill(text: currentArea.isEmpty ? '미설정' : currentArea, icon: Icons.business_rounded)),
                                  const SizedBox(width: 10),
                                  OpsActionButton(
                                    label: '재적용',
                                    icon: Icons.send_rounded,
                                    onPressed: _loading ? null : _resendToForeground,
                                    tonal: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        OpsPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OpsSectionTitle(
                                title: '운영 데이터 동기화',
                                subtitle: '주차 구역, 정산 타입, 월정기 사용 여부를 수동으로 재조회합니다.',
                                icon: Icons.sync_rounded,
                                trailing: _lastRefreshAt == null ? null : OpsStatusBadge(label: _formatLastSync(_lastRefreshAt!), color: cs.primary),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: OpsActionButton(
                                  label: _refreshing ? '새로고침 중' : '지금 새로고침',
                                  icon: Icons.refresh_rounded,
                                  onPressed: _loading || _refreshing ? null : _manualRefreshAll,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OpsPanel(
                          accentColor: cs.error,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const OpsSectionTitle(
                                title: '세션 종료',
                                subtitle: '포그라운드 서비스를 중지하고 로그인 화면으로 이동합니다.',
                                icon: Icons.logout_rounded,
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: OpsActionButton(
                                  label: '로그아웃',
                                  icon: Icons.logout_rounded,
                                  onPressed: _loading ? null : _logout,
                                  danger: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_locked)
                  Positioned.fill(
                    child: Container(
                      color: cs.scrim.withOpacity(.10),
                      alignment: Alignment.center,
                      child: _LockOverlay(onUnlock: _toggleLock),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;

  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: value ? cs.primary.withOpacity(.12) : cs.surfaceVariant.withOpacity(.45),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: value ? cs.primary.withOpacity(.22) : cs.outlineVariant.withOpacity(.75)),
              ),
              child: Icon(icon, color: value ? cs.primary : cs.onSurfaceVariant, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: (tt.bodyMedium ?? const TextStyle(fontSize: 14)).copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: (tt.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _LockOverlay extends StatelessWidget {
  final VoidCallback onUnlock;

  const _LockOverlay({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: OpsPanel(
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.primary.withOpacity(.22)),
              ),
              child: Icon(Icons.lock_rounded, color: cs.primary, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              '설정 잠금',
              style: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '운영 설정 변경을 막기 위해 잠겨 있습니다. 잠금 해제 후 TTS와 동기화 항목을 조정하세요.',
              textAlign: TextAlign.center,
              style: (tt.bodySmall ?? const TextStyle(fontSize: 12.5)).copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OpsActionButton(
                label: '잠금 해제',
                icon: Icons.lock_open_rounded,
                onPressed: onUnlock,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
