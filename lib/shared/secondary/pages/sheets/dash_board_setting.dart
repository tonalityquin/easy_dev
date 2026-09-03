import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/init/logout_helper.dart';
import '../../../../app/utils/operational_data_sync_workflow.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/selector/application/dev_auth.dart';
import '../../../operational_cache/domain/repositories/operational_local_repository.dart';
import '../../../secondary/widgets/ops_console_widgets.dart';
import '../../../tts/application/plate_tts_session_diagnostics.dart';
import '../../../tts/application/tts_sync_helper.dart';
import '../../../tts/application/tts_user_filters.dart';

class DashboardSetting extends StatefulWidget {
  const DashboardSetting({super.key});

  @override
  State<DashboardSetting> createState() => _DashboardSettingState();
}

class _DashboardSettingState extends State<DashboardSetting> {
  static const _prefsLockedKey = 'dashboard_setting_locked';
  static const _debugLimit = 200;

  TtsUserFilters _filters = TtsUserFilters.defaults();
  bool _loading = true;
  bool _applying = false;
  bool _refreshing = false;
  bool _resending = false;
  bool _locked = true;
  bool? _hasMonthlyParking;
  DateTime? _lastRefreshAt;
  String _operationalArea = '';
  bool _developerMode = false;
  final List<String> _debugLines = <String>[];

  @override
  void initState() {
    super.initState();
    _developerMode = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_onDeveloperModeChanged);
    PlateTtsSessionDiagnostics.ensureStarted();
    _logDebug('init', <String, Object?>{
      'developerMode': _developerMode,
      'surface': 'list',
    });
    _bootstrap();
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_onDeveloperModeChanged);
    super.dispose();
  }

  void _onDeveloperModeChanged() {
    if (!mounted) return;
    final next = DevAuth.devModeEnabled.value;
    if (_developerMode == next) return;
    _logDebug('developerModeChanged', <String, Object?>{
      'from': _developerMode,
      'to': next,
    });
    setState(() => _developerMode = next);
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${three(now.millisecond)}';
  }

  void _logDebug(
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    final details = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    final line = '[${_timestamp()}] [DashboardSetting] $event${details.isEmpty ? '' : ' $details'}';
    _debugLines.add(line);
    if (_debugLines.length > _debugLimit) {
      _debugLines.removeRange(0, _debugLines.length - _debugLimit);
    }
    debugPrint(line);
  }

  String get _debugPrintCode {
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  Future<void> _showDeveloperStatus() async {
    if (!_developerMode || !mounted) return;
    final area = context.read<AreaState>().currentArea.trim();
    final homeArea = context.read<UserState>().area.trim();
    _logDebug('statusSnapshot', <String, Object?>{
      'locked': _locked,
      'loading': _loading,
      'applying': _applying,
      'refreshing': _refreshing,
      'resending': _resending,
      'ttsEnabled': '$_enabledTtsCount/3',
      'parkingTts': _filters.parking,
      'departureTts': _filters.departure,
      'completedTts': _filters.completed,
      'homeArea': homeArea.isEmpty ? '-' : homeArea,
      'workArea': area.isEmpty ? '-' : area,
      'monthlyParking': _hasMonthlyParking,
      'lastSync': _lastRefreshAt?.toIso8601String() ?? '-',
      'surface': 'list_surface',
      'entryMotionMs': 230,
      'rowMotionMs': 190,
      'lockedContentReadable': true,
      'lockedInteractionDisabled': _locked,
      'pullRefreshEnabled': !_locked && !_loading && !_refreshing,
    });
    await StatusDialog.showSuccess(
      context,
      title: '설정 상태',
      description: '대시보드 설정 List Surface 상태와 최근 동작 로그입니다.',
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  Future<void> _bootstrap() async {
    _logDebug('bootstrapStart');
    await Future.wait(<Future<void>>[_loadLockState(), _load()]);
    _logDebug('bootstrapComplete', <String, Object?>{
      'locked': _locked,
      'ttsEnabled': '$_enabledTtsCount/3',
    });
  }

  Future<void> _loadLockState() async {
    final prefs = await SharedPreferences.getInstance();
    final locked = prefs.getBool(_prefsLockedKey);
    if (!mounted) return;
    setState(() => _locked = locked ?? true);
    _logDebug('lockLoaded', <String, Object?>{'locked': _locked});
  }

  Future<void> _saveLockState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLockedKey, value);
    _logDebug('lockPersisted', <String, Object?>{'locked': value});
  }

  Future<void> _load() async {
    _logDebug('loadStart');
    final loaded = await TtsUserFilters.load();
    final area = context.read<AreaState>().currentArea.trim();
    final meta = area.isEmpty
        ? null
        : await context.read<OperationalLocalRepository>().readAreaMeta(area);
    final hasMonthlyParking = meta?.hasMonthlyParking;
    final lastRefreshAt = meta?.syncedAt;
    _operationalArea = area;

    try {
      await TtsSyncHelper.apply(
        context,
        loaded,
        save: false,
        showSnackbar: false,
      );
      _logDebug('ttsInitialSyncSuccess', <String, Object?>{
        'parking': loaded.parking,
        'departure': loaded.departure,
        'completed': loaded.completed,
      });
    } catch (error, stackTrace) {
      _logDebug('ttsInitialSyncFailure', <String, Object?>{
        'error': error,
        'stack': stackTrace,
      });
    }

    if (!mounted) return;
    setState(() {
      _filters = loaded;
      _hasMonthlyParking = hasMonthlyParking;
      _lastRefreshAt = lastRefreshAt;
      _loading = false;
    });
    _logDebug('loadComplete', <String, Object?>{
      'area': area.isEmpty ? '-' : area,
      'monthlyParking': hasMonthlyParking,
      'lastSync': lastRefreshAt?.toIso8601String() ?? '-',
    });
  }

  Future<void> _reloadOperationalMeta(String area) async {
    final normalizedArea = area.trim();
    _logDebug('operationalMetaReloadStart', <String, Object?>{
      'area': normalizedArea.isEmpty ? '-' : normalizedArea,
    });
    final meta = normalizedArea.isEmpty
        ? null
        : await context
            .read<OperationalLocalRepository>()
            .readAreaMeta(normalizedArea);
    if (!mounted ||
        context.read<AreaState>().currentArea.trim() != normalizedArea) {
      _logDebug('operationalMetaReloadIgnored', <String, Object?>{
        'area': normalizedArea.isEmpty ? '-' : normalizedArea,
      });
      return;
    }
    setState(() {
      _operationalArea = normalizedArea;
      _hasMonthlyParking = meta?.hasMonthlyParking;
      _lastRefreshAt = meta?.syncedAt;
    });
    _logDebug('operationalMetaReloadComplete', <String, Object?>{
      'area': normalizedArea.isEmpty ? '-' : normalizedArea,
      'monthlyParking': meta?.hasMonthlyParking,
      'lastSync': meta?.syncedAt?.toIso8601String() ?? '-',
    });
  }

  Future<void> _apply(TtsUserFilters next) async {
    if (_applying || _locked) {
      _logDebug('ttsApplyBlocked', <String, Object?>{
        'applying': _applying,
        'locked': _locked,
      });
      return;
    }

    final previous = _filters;
    setState(() {
      _filters = next;
      _applying = true;
    });
    _logDebug('ttsApplyStart', <String, Object?>{
      'parking': '${previous.parking}->${next.parking}',
      'departure': '${previous.departure}->${next.departure}',
      'completed': '${previous.completed}->${next.completed}',
    });

    try {
      await TtsSyncHelper.apply(
        context,
        next,
        save: true,
        showSnackbar: false,
      );
      _logDebug('ttsApplySuccess', <String, Object?>{
        'enabled': '$_enabledTtsCount/3',
      });
    } catch (error, stackTrace) {
      _logDebug('ttsApplyFailure', <String, Object?>{
        'error': error,
        'stack': stackTrace,
      });
    } finally {
      if (!mounted) return;
      setState(() => _applying = false);
    }
  }

  Future<void> _resendToForeground() async {
    if (_resending || _locked) {
      _logDebug('foregroundResendBlocked', <String, Object?>{
        'resending': _resending,
        'locked': _locked,
      });
      return;
    }
    setState(() => _resending = true);
    _logDebug('foregroundResendStart', <String, Object?>{
      'ttsEnabled': '$_enabledTtsCount/3',
    });
    try {
      await TtsSyncHelper.apply(
        context,
        _filters,
        save: false,
        showSnackbar: false,
      );
      _logDebug('foregroundResendSuccess');
      if (!mounted) return;
      showSuccessSnackbar(
        context,
        '현재 설정을 포그라운드 서비스에 재적용했습니다.',
        useCommonUi: true,
      );
    } catch (error, stackTrace) {
      _logDebug('foregroundResendFailure', <String, Object?>{
        'error': error,
        'stack': stackTrace,
      });
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '포그라운드 서비스 재적용에 실패했습니다.',
        useCommonUi: true,
      );
    } finally {
      if (!mounted) return;
      setState(() => _resending = false);
    }
  }

  Future<void> _showTtsStatus() async {
    _logDebug('ttsStatusOpen');
    await PlateTtsSessionDiagnostics.showStatus(
      context,
      area: context.read<AreaState>().currentArea.trim(),
      filters: _filters,
    );
  }

  Future<void> _manualRefreshAll() async {
    if (_refreshing || _locked) {
      _logDebug('manualRefreshBlocked', <String, Object?>{
        'refreshing': _refreshing,
        'locked': _locked,
      });
      return;
    }

    setState(() => _refreshing = true);
    _logDebug('manualRefreshStart', <String, Object?>{
      'area': context.read<AreaState>().currentArea.trim(),
    });
    try {
      final result = await OperationalDataSyncWorkflow.run(context: context);
      _logDebug('manualRefreshResult', <String, Object?>{
        'result': '$result',
      });
      if (result == OperationalDataSyncResult.completed && mounted) {
        await _load();
      }
    } catch (error, stackTrace) {
      _logDebug('manualRefreshFailure', <String, Object?>{
        'error': error,
        'stack': stackTrace,
      });
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);
    }
  }


  Future<void> _handlePullRefresh() async {
    if (_locked) {
      _logDebug('pullRefreshBlocked', <String, Object?>{'locked': true});
      return;
    }
    await _manualRefreshAll();
  }

  Future<void> _logout() async {
    if (_locked) {
      _logDebug('logoutBlocked', <String, Object?>{'locked': true});
      return;
    }
    _logDebug('logoutStart');
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(seconds: 1),
    );
  }

  Future<void> _toggleLock() async {
    if (_loading) return;
    final next = !_locked;
    _logDebug('lockToggle', <String, Object?>{
      'from': _locked,
      'to': next,
    });
    setState(() => _locked = next);
    await _saveLockState(next);
  }

  String _formatLastSync(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = dt.toLocal();
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _formatLastSyncTime(DateTime? dt) {
    if (dt == null) return '-';
    final value = _formatLastSync(dt);
    return value.length >= 16 ? value.substring(11) : value;
  }

  int get _enabledTtsCount {
    var count = 0;
    if (_filters.parking) count++;
    if (_filters.departure) count++;
    if (_filters.completed) count++;
    return count;
  }

  Widget _buildListContent(
    BuildContext context, {
    required String currentArea,
    required bool? currentIsHeadquarter,
    required String homeArea,
  }) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final monthlyLabel = _hasMonthlyParking == null
        ? '대기'
        : _hasMonthlyParking!
            ? '사용'
            : '없음';
    final workTypeLabel = currentIsHeadquarter == null
        ? '확인 중'
        : currentIsHeadquarter
            ? '본사'
            : '지사';
    final sections = <Widget>[
      if (currentArea.isEmpty)
        _SettingsNoticeRow(
          icon: Icons.info_outline_rounded,
          label: '지역 설정 필요',
          color: cs.error,
        ),
      _SettingsSection(
        title: '상태',
        first: true,
        children: <Widget>[
          _SettingsValueRow(
            icon: Icons.record_voice_over_rounded,
            label: 'TTS',
            value: _applying ? null : '$_enabledTtsCount/3',
            busy: _applying,
            valueColor: cs.primary,
          ),
          _SettingsValueRow(
            icon: _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            label: '설정 잠금',
            value: _locked ? 'ON' : 'OFF',
            valueColor: _locked ? cs.error : cs.primary,
          ),
          _SettingsValueRow(
            icon: Icons.local_parking_rounded,
            label: '월정기',
            value: monthlyLabel,
            valueColor: _hasMonthlyParking == true
                ? cs.primary
                : cs.onSurfaceVariant,
          ),
          _SettingsValueRow(
            icon: Icons.sync_rounded,
            label: '마지막 동기화',
            value: _formatLastSyncTime(_lastRefreshAt),
          ),
        ],
      ),
      _SettingsSection(
        title: 'TTS 알림',
        children: <Widget>[
          _SettingsSwitchRow(
            icon: Icons.local_parking_rounded,
            label: '입차 요청',
            value: _filters.parking,
            onChanged: _locked || _applying
                ? null
                : (value) => _apply(_filters.copyWith(parking: value)),
          ),
          _SettingsSwitchRow(
            icon: Icons.exit_to_app_rounded,
            label: '출차 요청',
            value: _filters.departure,
            onChanged: _locked || _applying
                ? null
                : (value) => _apply(_filters.copyWith(departure: value)),
          ),
          _SettingsSwitchRow(
            icon: Icons.done_all_rounded,
            label: '출차 완료 2회',
            value: _filters.completed,
            onChanged: _locked || _applying
                ? null
                : (value) => _apply(_filters.copyWith(completed: value)),
          ),
        ],
      ),
      _SettingsSection(
        title: '운영 지점',
        children: <Widget>[
          _SettingsValueRow(
            icon: Icons.apartment_rounded,
            label: '소속',
            value: homeArea.isEmpty ? '미설정' : homeArea,
          ),
          _SettingsValueRow(
            icon: Icons.business_rounded,
            label: '근무',
            value: currentArea.isEmpty ? '미설정' : currentArea,
          ),
          _SettingsValueRow(
            icon: Icons.hub_rounded,
            label: '운영 유형',
            value: workTypeLabel,
            valueColor: currentIsHeadquarter == null
                ? cs.onSurfaceVariant
                : currentIsHeadquarter
                    ? cs.primary
                    : cs.tertiary,
          ),
          _SettingsActionRow(
            icon: Icons.sync_alt_rounded,
            label: '현재 설정 재적용',
            enabled: !_locked && !_loading && !_resending,
            busy: _resending,
            onTap: _resendToForeground,
          ),
        ],
      ),
      _SettingsSection(
        title: '데이터',
        children: <Widget>[
          _SettingsValueRow(
            icon: Icons.schedule_rounded,
            label: '마지막 동기화',
            value: _lastRefreshAt == null
                ? '-'
                : _formatLastSync(_lastRefreshAt!),
          ),
          _SettingsActionRow(
            icon: Icons.refresh_rounded,
            label: '지금 새로고침',
            enabled: !_locked && !_loading && !_refreshing,
            busy: _refreshing,
            onTap: _manualRefreshAll,
          ),
        ],
      ),
      _SettingsSection(
        title: '세션',
        children: <Widget>[
          _SettingsActionRow(
            icon: Icons.logout_rounded,
            label: '로그아웃',
            enabled: !_locked && !_loading,
            danger: true,
            onTap: _logout,
          ),
        ],
      ),
      const SizedBox(height: 24),
    ];

    final listView = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      children: sections,
    );
    final list = _locked
        ? listView
        : RefreshIndicator(
            onRefresh: _handlePullRefresh,
            color: cs.primary,
            child: listView,
          );

    return Column(
      children: [
        AnimatedSize(
          duration: duration,
          curve: CommonUiMotion.enter,
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: CommonUiMotion.enter,
            switchOutCurve: CommonUiMotion.exit,
            transitionBuilder: (child, animation) {
              if (reduceMotion) {
                return FadeTransition(opacity: animation, child: child);
              }
              final offset = Tween<Offset>(
                begin: const Offset(0, -.12),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: CommonUiMotion.enter,
                ),
              );
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: _locked
                ? _SettingsLockNotice(
                    key: const ValueKey('settings-lock-notice'),
                    onUnlock: _toggleLock,
                  )
                : const SizedBox(
                    key: ValueKey('settings-lock-notice-hidden'),
                  ),
          ),
        ),
        AnimatedSize(
          duration: duration,
          curve: CommonUiMotion.enter,
          child: _loading
              ? LinearProgressIndicator(
                  minHeight: 2,
                  color: cs.primary,
                  backgroundColor: cs.surfaceContainerHighest.withOpacity(.45),
                )
              : const SizedBox(height: 2),
        ),
        Expanded(
          child: AnimatedOpacity(
            opacity: _loading ? .58 : 1,
            duration: duration,
            curve: CommonUiMotion.enter,
            child: IgnorePointer(
              ignoring: _loading,
              child: CommonAnimatedReveal(
                offset: const Offset(0, .02),
                child: list,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentArea =
        context.select<AreaState, String>((state) => state.currentArea.trim());
    final currentIsHeadquarter = context.select<AreaState, bool?>(
      (state) => state.currentRecord?.isHeadquarter,
    );
    final homeArea = context.select<UserState, String>((state) => state.area.trim());

    if (_operationalArea != currentArea) {
      _operationalArea = currentArea;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _reloadOperationalMeta(currentArea);
        }
      });
    }

    final areaLabel = currentArea.isEmpty ? '지역 미설정' : currentArea;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return OpsConsoleScaffold(
      title: '대시보드 설정',
      icon: Icons.dashboard_customize_rounded,
      areaLabel: areaLabel,
      loading: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            transitionBuilder: (child, animation) {
              if (reduceMotion) {
                return FadeTransition(opacity: animation, child: child);
              }
              final scale = Tween<double>(begin: .9, end: 1).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: CommonUiMotion.enter,
                ),
              );
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: scale, child: child),
              );
            },
            child: !_developerMode
                ? const SizedBox(key: ValueKey('setting-dev-actions-hidden'))
                : Row(
                    key: const ValueKey('setting-dev-actions-visible'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CommonIconButton(
                        icon: Icons.record_voice_over_rounded,
                        tooltip: 'TTS 상태',
                        onPressed: _showTtsStatus,
                        haptic: CommonHaptic.selection,
                      ),
                      const SizedBox(width: 2),
                      CommonIconButton(
                        icon: Icons.bug_report_rounded,
                        tooltip: '설정 상태',
                        onPressed: _showDeveloperStatus,
                        haptic: CommonHaptic.selection,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
          ),
          CommonIconButton(
            icon: _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            tooltip: _locked ? '잠금 해제' : '잠금',
            onPressed: _loading ? null : _toggleLock,
            selected: !_locked,
            haptic: CommonHaptic.selection,
          ),
        ],
      ),
      body: _buildListContent(
        context,
        currentArea: currentArea,
        currentIsHeadquarter: currentIsHeadquarter,
        homeArea: homeArea,
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.first = false,
  });

  final String title;
  final List<Widget> children;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      rows.add(children[index]);
      if (index != children.length - 1) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant.withOpacity(.38),
            ),
          ),
        );
      }
    }
    return Padding(
      padding: EdgeInsets.only(top: first ? 8 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
            child: Text(
              title,
              style: (tt.labelLarge ?? const TextStyle(fontSize: 13)).copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: .1,
              ),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _SettingsValueRow extends StatelessWidget {
  const _SettingsValueRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: (tt.bodyMedium ?? const TextStyle(fontSize: 14)).copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: duration,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              transitionBuilder: (child, animation) {
                if (reduceMotion) {
                  return FadeTransition(opacity: animation, child: child);
                }
                final offset = Tween<Offset>(
                  begin: const Offset(0, .14),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: CommonUiMotion.enter,
                  ),
                );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: busy
                  ? SizedBox(
                      key: ValueKey('busy-$label'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    )
                  : Text(
                      value ?? '-',
                      key: ValueKey('$label-${value ?? '-'}'),
                      textAlign: TextAlign.right,
                      style: (tt.bodyMedium ?? const TextStyle(fontSize: 14))
                          .copyWith(
                        color: valueColor ?? cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Icon(
                    icon,
                    size: 18,
                    color: onChanged == null
                        ? cs.onSurface.withOpacity(.38)
                        : value
                            ? cs.primary
                            : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: (tt.bodyMedium ?? const TextStyle(fontSize: 14))
                        .copyWith(
                      color: onChanged == null
                          ? cs.onSurface.withOpacity(.46)
                          : cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch.adaptive(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.busy = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final Future<void> Function() onTap;
  final bool busy;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final activeColor = danger ? cs.error : cs.onSurface;
    final disabledColor = cs.onSurface.withOpacity(.38);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled && !busy
            ? () {
                onTap();
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Icon(
                    icon,
                    size: 18,
                    color: enabled ? activeColor : disabledColor,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: (tt.bodyMedium ?? const TextStyle(fontSize: 14))
                        .copyWith(
                      color: enabled ? activeColor : disabledColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  transitionBuilder: (child, animation) {
                    final scale = Tween<double>(begin: .92, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: CommonUiMotion.enter,
                      ),
                    );
                    return FadeTransition(
                      opacity: animation,
                      child: reduceMotion
                          ? child
                          : ScaleTransition(scale: scale, child: child),
                    );
                  },
                  child: busy
                      ? SizedBox(
                          key: ValueKey('action-busy-$label'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: danger ? cs.error : cs.primary,
                          ),
                        )
                      : Icon(
                          key: ValueKey('action-icon-$label'),
                          danger
                              ? Icons.logout_rounded
                              : Icons.refresh_rounded,
                          size: 18,
                          color: enabled ? activeColor : disabledColor,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsLockNotice extends StatelessWidget {
  const _SettingsLockNotice({super.key, required this.onUnlock});

  final Future<void> Function() onUnlock;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.errorContainer.withOpacity(.22),
      child: InkWell(
        onTap: () {
          onUnlock();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: cs.error.withOpacity(.18),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_rounded, size: 18, color: cs.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '설정이 잠겨 있습니다',
                  style: (tt.bodySmall ?? const TextStyle(fontSize: 12.5))
                      .copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '잠금 해제',
                style: (tt.labelMedium ?? const TextStyle(fontSize: 12))
                    .copyWith(
                  color: cs.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 18, color: cs.error),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsNoticeRow extends StatelessWidget {
  const _SettingsNoticeRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            SizedBox(width: 26, child: Icon(icon, size: 18, color: color)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: (tt.bodyMedium ?? const TextStyle(fontSize: 14)).copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
