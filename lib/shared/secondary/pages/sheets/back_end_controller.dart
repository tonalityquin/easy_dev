import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/snackbar_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/selector/application/dev_auth.dart';
import '../../../plate/domain/repositories/plate_repository.dart';
import '../../widgets/ops_console_dialogs.dart';
import '../../widgets/ops_console_widgets.dart';

class BackEndController extends StatefulWidget {
  const BackEndController({super.key});

  @override
  State<BackEndController> createState() => _BackEndControllerState();
}

class _BackEndControllerState extends State<BackEndController> {
  static const _debugLimit = 200;

  bool _checkingDevAuth = true;
  bool _devAuthorized = false;
  bool _developerMode = false;
  bool _rebuildingMonthlyView = false;
  final List<String> _debugLines = <String>[];

  @override
  void initState() {
    super.initState();
    _developerMode = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_onDeveloperModeChanged);
    _logDebug('init', <String, Object?>{
      'developerMode': _developerMode,
      'surface': 'list_surface',
    });
    _loadDevAuth();
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
    setState(() {
      _developerMode = next;
      if (!next) {
        _devAuthorized = false;
        _checkingDevAuth = false;
      }
    });
    if (next) {
      _loadDevAuth();
    }
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
    final line =
        '[${_timestamp()}] [BackEndController] $event${details.isEmpty ? '' : ' $details'}';
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
    _logDebug('statusSnapshot', <String, Object?>{
      'developerMode': _developerMode,
      'devAuthorized': _devAuthorized,
      'checkingDevAuth': _checkingDevAuth,
      'rebuildingMonthlyView': _rebuildingMonthlyView,
      'actionEnabled': _devAuthorized &&
          !_checkingDevAuth &&
          !_rebuildingMonthlyView,
      'surface': 'list_surface',
      'entryMotionMs': 230,
      'rowMotionMs': 190,
      'progressStrip': _checkingDevAuth || _rebuildingMonthlyView,
      'confirmDestructive': true,
    });
    await StatusDialog.showSuccess(
      context,
      title: '백엔드 상태',
      description: '백엔드 List Surface 상태와 최근 동작 로그입니다.',
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  Future<void> _loadDevAuth() async {
    if (mounted) {
      setState(() => _checkingDevAuth = true);
    }
    _logDebug('devAuthCheckStart');
    final devAuthorized = await DevAuth.isDeveloperLoggedIn();
    if (!mounted) return;
    setState(() {
      _developerMode = DevAuth.devModeEnabled.value;
      _devAuthorized = devAuthorized;
      _checkingDevAuth = false;
    });
    _logDebug('devAuthCheckComplete', <String, Object?>{
      'developerMode': _developerMode,
      'authorized': devAuthorized,
    });
  }

  Future<void> _rebuildMonthlyPlateStatusViews() async {
    if (_checkingDevAuth || !_devAuthorized || _rebuildingMonthlyView) {
      _logDebug('monthlyViewRebuildBlocked', <String, Object?>{
        'checkingDevAuth': _checkingDevAuth,
        'devAuthorized': _devAuthorized,
        'rebuilding': _rebuildingMonthlyView,
      });
      return;
    }

    _logDebug('monthlyViewRebuildRequested');
    final ok = await showOpsConfirmDialog(
      context: context,
      title: '정기 주차 View 전체 재생성',
      message:
          'monthly_plate_status 원본 기준으로 monthly_plate_status_view 지역별 문서를 생성하거나 덮어씁니다. 계속하시겠습니까?',
      confirmLabel: '실행',
      icon: Icons.sync_alt_rounded,
      destructive: true,
    );
    if (!ok || !mounted) {
      _logDebug('monthlyViewRebuildCancelled');
      return;
    }

    setState(() => _rebuildingMonthlyView = true);
    _logDebug('monthlyViewRebuildStart');
    try {
      final result = await context
          .read<PlateRepository>()
          .rebuildAllMonthlyPlateStatusViews();
      if (!mounted) return;
      _logDebug('monthlyViewRebuildSuccess', <String, Object?>{
        'areaCount': result.areaCount,
        'itemCount': result.itemCount,
        'skippedCount': result.skippedCount,
        'deletedViewCount': result.deletedViewCount,
      });
      showSuccessSnackbar(
        context,
        '정기 주차 View 재생성 완료: 지역 ${result.areaCount}개 / 정기권 ${result.itemCount}건 / 건너뜀 ${result.skippedCount}건 / 삭제 ${result.deletedViewCount}건',
        useCommonUi: true,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      _logDebug('monthlyViewRebuildFailure', <String, Object?>{
        'error': error,
        'stack': stackTrace,
      });
      showFailedSnackbar(
        context,
        '정기 주차 View 재생성에 실패했습니다. ${error.toString()}',
        useCommonUi: true,
      );
    } finally {
      if (mounted) {
        setState(() => _rebuildingMonthlyView = false);
        _logDebug('monthlyViewRebuildComplete');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final devStatus = _checkingDevAuth
        ? '확인 중'
        : _devAuthorized
            ? '활성'
            : '비활성';
    final devStatusColor = _checkingDevAuth
        ? tokens.textSecondary
        : _devAuthorized
            ? tokens.success
            : tokens.danger;
    final workStatus = _rebuildingMonthlyView ? '실행 중' : '대기';
    final workStatusColor =
        _rebuildingMonthlyView ? tokens.accent : tokens.textSecondary;
    final busy = _checkingDevAuth || _rebuildingMonthlyView;

    return OpsConsoleScaffold(
      title: '실시간 컨트롤러',
      subtitle: 'DEBUG 세션 상태와 운영 데이터 유지보수 기능을 확인합니다.',
      icon: Icons.settings_ethernet_rounded,
      trailing: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) {
          if (reduceMotion) {
            return FadeTransition(opacity: animation, child: child);
          }
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: .9, end: 1).animate(animation),
              child: child,
            ),
          );
        },
        child: _developerMode
            ? IconButton(
                key: const ValueKey<String>('backend-dev-status'),
                onPressed: _showDeveloperStatus,
                icon: Icon(
                  Icons.bug_report_outlined,
                  color: tokens.iconSecondary,
                  size: 20,
                ),
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('backend-dev-status-hidden'),
              ),
      ),
      body: Column(
        children: [
          _BackendProgressStrip(
            visible: busy,
            reduceMotion: reduceMotion,
          ),
          Expanded(
            child: CommonAnimatedReveal(
              duration: CommonUiMotion.selection,
              offset: const Offset(0, .018),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                children: [
                  _BackendListSection(
                    title: '상태',
                    rows: [
                      _BackendValueRow(
                        label: '개발자 모드',
                        value: devStatus,
                        valueColor: devStatusColor,
                      ),
                      _BackendValueRow(
                        label: 'View 작업',
                        value: workStatus,
                        valueColor: workStatusColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _BackendListSection(
                    title: '실시간 구독',
                    rows: [
                      _BackendValueRow(
                        label: '스냅샷 구독',
                        value: '사용 안 함',
                      ),
                      _BackendValueRow(
                        label: 'PlateState 구독',
                        value: '제거됨',
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _BackendListSection(
                    title: '정기 주차 View',
                    rows: [
                      _BackendValueRow(
                        label: '작업 상태',
                        value: workStatus,
                        valueColor: workStatusColor,
                      ),
                      _BackendActionRow(
                        label: '전체 재생성',
                        enabled: _devAuthorized &&
                            !_checkingDevAuth &&
                            !_rebuildingMonthlyView,
                        busy: _rebuildingMonthlyView,
                        onTap: _rebuildMonthlyPlateStatusViews,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackendProgressStrip extends StatelessWidget {
  const _BackendProgressStrip({
    required this.visible,
    required this.reduceMotion,
  });

  final bool visible;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return SizedBox(
      height: 2,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        child: visible
            ? reduceMotion
                ? ColoredBox(
                    key: const ValueKey<String>('backend-progress-static'),
                    color: tokens.accent,
                  )
                : LinearProgressIndicator(
                    key: const ValueKey<String>('backend-progress-active'),
                    minHeight: 2,
                    color: tokens.accent,
                    backgroundColor: tokens.transparent,
                  )
            : const SizedBox.expand(
                key: ValueKey<String>('backend-progress-idle'),
              ),
      ),
    );
  }
}

class _BackendListSection extends StatelessWidget {
  const _BackendListSection({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
          child: Text(
            title,
            style: textTheme.labelMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (var index = 0; index < rows.length; index++) ...[
          rows[index],
          if (index < rows.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              color: tokens.borderSubtle.withOpacity(.72),
            ),
        ],
      ],
    );
  }
}

class _BackendValueRow extends StatelessWidget {
  const _BackendValueRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) {
                  if (reduceMotion) {
                    return FadeTransition(opacity: animation, child: child);
                  }
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .14),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  value,
                  key: ValueKey<String>(value),
                  textAlign: TextAlign.end,
                  style: textTheme.bodyMedium?.copyWith(
                    color: valueColor ?? tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackendActionRow extends StatelessWidget {
  const _BackendActionRow({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final foreground = enabled ? tokens.textPrimary : tokens.textDisabled;
    final iconColor = enabled ? tokens.accent : tokens.iconDisabled;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 54),
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 24,
                height: 24,
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  transitionBuilder: (child, animation) {
                    if (reduceMotion) {
                      return FadeTransition(opacity: animation, child: child);
                    }
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: .92, end: 1).animate(
                          animation,
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: busy
                      ? SizedBox(
                          key: const ValueKey<String>('backend-action-busy'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: tokens.accent,
                          ),
                        )
                      : Icon(
                          Icons.sync_alt_rounded,
                          key: const ValueKey<String>('backend-action-idle'),
                          size: 21,
                          color: iconColor,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
