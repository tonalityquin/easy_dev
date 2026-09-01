import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/tts/application/plate_tts_session_diagnostics.dart';
import '../../../account/applications/user_state.dart';
import '../../../launcher/application/app_mode_definition.dart';
import '../../../launcher/application/app_mode_registry.dart';
import '../../../launcher/application/launcher_diagnostics.dart';
import '../../../selector/application/dev_auth.dart';
import '../../../headquarter/application/snapshot/headquarter_snapshot_repository.dart';

class HeadquarterWorkAreaDockResult {
  const HeadquarterWorkAreaDockResult.navigate({
    required this.areaName,
    required this.modeKey,
  })  : openSecondary = false,
        openSprint = false;

  const HeadquarterWorkAreaDockResult.openSecondary()
      : areaName = '',
        modeKey = '',
        openSecondary = true,
        openSprint = false;

  const HeadquarterWorkAreaDockResult.openSprint()
      : areaName = '',
        modeKey = '',
        openSecondary = false,
        openSprint = true;

  final String areaName;
  final String modeKey;
  final bool openSecondary;
  final bool openSprint;
}

Future<HeadquarterWorkAreaDockResult?> showHeadquarterWorkAreaSideDock({
  required BuildContext context,
  required String currentModeKey,
  required String currentScreen,
}) {
  return showCommonLeftSideDock<HeadquarterWorkAreaDockResult>(
    context: context,
    barrierLabel: '업무 지역 선택',
    maxWidth: 440,
    widthFactor: 0.96,
    builder: (_) => HeadquarterWorkAreaSideDock(
      currentModeKey: currentModeKey,
      currentScreen: currentScreen,
    ),
  );
}

class HeadquarterWorkAreaSideDock extends StatefulWidget {
  const HeadquarterWorkAreaSideDock({
    super.key,
    required this.currentModeKey,
    required this.currentScreen,
  });

  final String currentModeKey;
  final String currentScreen;

  @override
  State<HeadquarterWorkAreaSideDock> createState() =>
      _HeadquarterWorkAreaSideDockState();
}

class _HeadquarterWorkAreaSideDockState
    extends State<HeadquarterWorkAreaSideDock> {
  final List<String> _debugLines = <String>[];
  bool _loading = true;
  bool _developerMode = false;
  String _division = '';
  String _downloadedAtIso = '';
  String? _error;
  _WorkAreaViewData? _selectedArea;
  List<_WorkAreaViewData> _areas = const <_WorkAreaViewData>[];

  @override
  void initState() {
    super.initState();
    _log(
      'mounted screen=${widget.currentScreen} currentMode=${widget.currentModeKey} source=sqlite areaFirst=true firebaseRead=0 firebaseWrite=0',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  void _log(String message) {
    final line =
        '[HQ-WORK-AREA-DOCK][${DateTime.now().toIso8601String()}] $message';
    _debugLines.add(line);
    if (_debugLines.length > 240) {
      _debugLines.removeRange(0, _debugLines.length - 240);
    }
    debugPrint(line);
  }

  Future<void> _load() async {
    if (!mounted) return;
    final userState = context.read<UserState>();
    final session = userState.session;
    final division = userState.division.trim();
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    if (session == null || division.isEmpty) {
      setState(() {
        _developerMode = developerMode;
        _division = division;
        _areas = const <_WorkAreaViewData>[];
        _loading = false;
        _error = 'session_or_division_missing';
      });
      _log('load_blocked reason=session_or_division_missing');
      return;
    }

    try {
      _log('snapshot_read_start division=$division');
      final snapshot =
          await HeadquarterSnapshotRepository.instance.readSnapshot(division);
      if (!mounted) return;
      if (snapshot == null) {
        setState(() {
          _developerMode = developerMode;
          _division = division;
          _areas = const <_WorkAreaViewData>[];
          _downloadedAtIso = '';
          _loading = false;
          _error = 'snapshot_missing';
        });
        _log(
          'snapshot_read_complete result=missing division=$division firebaseRead=0 firebaseWrite=0',
        );
        return;
      }

      final allowedAreas = session.areas
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      final accountModes = AppModeRegistry.supportedModes(
        session.modes,
        allowedIds: const <String>{'single', 'double', 'triple', 'minor'},
      );
      final accountModeIds = accountModes.map((mode) => mode.id).toSet();
      final areas = <_WorkAreaViewData>[];
      for (final area in snapshot.areas) {
        final areaName = area.name.trim();
        if (areaName.isEmpty || !allowedAreas.contains(areaName)) continue;
        final modes = AppModeRegistry.supportedModes(
          area.modes,
          allowedIds: accountModeIds,
        );
        if (!area.isHeadquarter && modes.isEmpty) continue;
        areas.add(
          _WorkAreaViewData(
            areaName: areaName,
            isHeadquarter: area.isHeadquarter,
            modes: List<AppModeDefinition>.unmodifiable(modes),
          ),
        );
      }
      areas.sort((a, b) {
        if (a.isHeadquarter != b.isHeadquarter) {
          return a.isHeadquarter ? -1 : 1;
        }
        return a.areaName.toLowerCase().compareTo(b.areaName.toLowerCase());
      });
      setState(() {
        _developerMode = developerMode;
        _division = division;
        _downloadedAtIso = snapshot.downloadedAtIso;
        _areas = List<_WorkAreaViewData>.unmodifiable(areas);
        _loading = false;
        _error = null;
      });
      _log(
        'snapshot_read_complete division=$division areas=${areas.length} downloadedAt=${snapshot.downloadedAtIso} userAreas=${allowedAreas.length} userModes=${accountModeIds.join(',')} firebaseRead=0 firebaseWrite=0',
      );
      for (final area in areas) {
        _log(
          'area_ready area=${area.areaName} isHeadquarter=${area.isHeadquarter} modes=${area.modes.map((mode) => mode.id).join(',')}',
        );
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _developerMode = developerMode;
        _division = division;
        _areas = const <_WorkAreaViewData>[];
        _loading = false;
        _error = error.toString();
      });
      _log('snapshot_read_failure error=$error stack=$stackTrace');
    }
  }

  Future<void> _showStatus() async {
    if (!_developerMode || !mounted) return;
    HapticFeedback.mediumImpact();
    _log(
      'status_open division=$_division areaCount=${_areas.length} selected=${_selectedArea?.areaName ?? ''} downloadedAt=$_downloadedAtIso error=${_error ?? ''}',
    );
    final lines = <String>[
      ...LauncherDiagnostics.lines,
      ...PlateTtsSessionDiagnostics.lines,
      ..._debugLines,
    ];
    final code = lines.isEmpty
        ? 'debugPrint(${jsonEncode('[HQ-WORK-AREA-DOCK] 기록된 로그가 없습니다.')});'
        : lines
            .map((line) => 'debugPrint(${jsonEncode(line)});')
            .join('\n');
    await StatusDialog.showSuccess(
      context,
      title: '업무 지역 선택 상태',
      description:
          'SQLite Snapshot 지역 선택과 본사 독립 활성화 상태를 확인합니다.',
      copyText: code,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  void _selectArea(_WorkAreaViewData area) {
    _log(
      'area_selected area=${area.areaName} isHeadquarter=${area.isHeadquarter} modes=${area.modes.map((mode) => mode.id).join(',')}',
    );
    if (area.isHeadquarter) {
      HapticFeedback.selectionClick();
      _log(
        'headquarter_selected area=${area.areaName} modeIndependent=true modeKey=none persistMode=false publishMode=false',
      );
      Navigator.of(context).pop(
        HeadquarterWorkAreaDockResult.navigate(
          areaName: area.areaName,
          modeKey: '',
        ),
      );
      return;
    }
    if (area.modes.isEmpty) {
      setState(() => _selectedArea = area);
      return;
    }
    if (area.modes.length == 1) {
      final mode = area.modes.first;
      Navigator.of(context).pop(
        HeadquarterWorkAreaDockResult.navigate(
          areaName: area.areaName,
          modeKey: mode.id,
        ),
      );
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _selectedArea = area);
  }

  void _selectMode(AppModeDefinition mode) {
    final area = _selectedArea;
    if (area == null) return;
    _log('mode_selected area=${area.areaName} mode=${mode.id}');
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(
      HeadquarterWorkAreaDockResult.navigate(
        areaName: area.areaName,
        modeKey: mode.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.component;
    return SafeArea(
      child: ColoredBox(
        color: tokens.canvas,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: duration,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(-0.06, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _selectedArea == null
                        ? Text(
                            '업무 지역 선택',
                            key: const ValueKey<String>('area-title'),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                          )
                        : Text(
                            _selectedArea!.areaName,
                            key: ValueKey<String>('mode-title-${_selectedArea!.areaName}'),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                  ),
                  const Spacer(),
                  if (_developerMode)
                    IconButton(
                      onPressed: _showStatus,
                      icon: const Icon(Icons.monitor_heart_outlined),
                      color: tokens.textSecondary,
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: tokens.textSecondary,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.borderSubtle),
            Expanded(
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) {
                  if (reduceMotion) return child;
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _selectedArea == null
                    ? _buildAreaList(tokens, reduceMotion)
                    : _buildModeList(tokens, reduceMotion, _selectedArea!),
              ),
            ),
            Divider(height: 1, color: tokens.borderSubtle),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  if (_selectedArea != null)
                    Expanded(
                      child: CommonButton(
                        label: '지역 목록',
                        icon: Icons.arrow_back_rounded,
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedArea = null);
                        },
                        variant: CommonButtonVariant.secondary,
                        haptic: CommonHaptic.none,
                      ),
                    ),
                  if (_selectedArea != null) const SizedBox(width: 8),
                  Expanded(
                    child: CommonButton(
                      label: '운영 관리',
                      icon: Icons.tune_rounded,
                      onPressed: () => Navigator.of(context).pop(
                        const HeadquarterWorkAreaDockResult.openSecondary(),
                      ),
                      variant: CommonButtonVariant.tertiary,
                      haptic: CommonHaptic.selection,
                    ),
                  ),
                  if (_developerMode) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: CommonButton(
                        label: '스프린트',
                        icon: Icons.bolt_rounded,
                        onPressed: () => Navigator.of(context).pop(
                          const HeadquarterWorkAreaDockResult.openSprint(),
                        ),
                        variant: CommonButtonVariant.tertiary,
                        haptic: CommonHaptic.selection,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAreaList(CommonUiTokens tokens, bool reduceMotion) {
    if (_loading) {
      return Center(
        key: const ValueKey<String>('loading'),
        child: CircularProgressIndicator(color: tokens.accent),
      );
    }
    if (_error != null || _areas.isEmpty) {
      return Center(
        key: const ValueKey<String>('empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error == 'snapshot_missing'
                ? '본사 다운로드 데이터가 없습니다.'
                : '선택할 수 있는 업무 지역이 없습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      );
    }
    return ListView.separated(
      key: const ValueKey<String>('area-list'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: _areas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final area = _areas[index];
        return CommonAnimatedReveal(
          offset: reduceMotion ? Offset.zero : const Offset(0.035, 0),
          child: _WorkAreaCard(
            area: area,
            currentArea: context.read<UserState>().currentArea,
            onPressed: () => _selectArea(area),
          ),
        );
      },
    );
  }

  Widget _buildModeList(
    CommonUiTokens tokens,
    bool reduceMotion,
    _WorkAreaViewData area,
  ) {
    if (area.modes.isEmpty) {
      return Center(
        key: ValueKey<String>('mode-empty-${area.areaName}'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '이 지역에서 사용할 수 있는 업무 모드가 없습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      );
    }
    return ListView.separated(
      key: ValueKey<String>('mode-list-${area.areaName}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: area.modes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final mode = area.modes[index];
        return CommonAnimatedReveal(
          offset: reduceMotion ? Offset.zero : const Offset(0.035, 0),
          child: CommonButton(
            label: '${mode.koreanName} · ${mode.englishName}',
            icon: _modeIcon(mode.id),
            onPressed: () => _selectMode(mode),
            expand: true,
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.none,
          ),
        );
      },
    );
  }

  IconData _modeIcon(String modeKey) {
    switch (modeKey) {
      case 'single':
        return Icons.looks_one_rounded;
      case 'double':
        return Icons.view_week_rounded;
      case 'triple':
        return Icons.apartment_rounded;
      case 'minor':
        return Icons.tune_rounded;
      default:
        return Icons.work_outline_rounded;
    }
  }
}

class _WorkAreaCard extends StatefulWidget {
  const _WorkAreaCard({
    required this.area,
    required this.currentArea,
    required this.onPressed,
  });

  final _WorkAreaViewData area;
  final String currentArea;
  final VoidCallback onPressed;

  @override
  State<_WorkAreaCard> createState() => _WorkAreaCardState();
}

class _WorkAreaCardState extends State<_WorkAreaCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.press;
    final active = widget.currentArea.trim() == widget.area.areaName;
    return Semantics(
      button: true,
      label: widget.area.isHeadquarter
          ? '본사 선택'
          : '${widget.area.areaName} 업무 지역 선택',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.selectionClick();
          widget.onPressed();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: duration,
          curve: CommonUiMotion.standard,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
            curve: CommonUiMotion.standard,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: active ? tokens.accentContainer : tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(CommonUiShapes.card),
              border: Border.all(
                color: active ? tokens.accent : tokens.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.area.isHeadquarter
                        ? tokens.accentContainer
                        : tokens.surface,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  ),
                  child: Icon(
                    widget.area.isHeadquarter
                        ? Icons.corporate_fare_rounded
                        : Icons.location_on_outlined,
                    color: widget.area.isHeadquarter
                        ? tokens.accent
                        : tokens.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.area.isHeadquarter
                                  ? '본사'
                                  : widget.area.areaName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          if (widget.area.isHeadquarter) ...[
                            const SizedBox(width: 8),
                            Text(
                              widget.area.areaName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final mode in widget.area.modes)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surface,
                                borderRadius:
                                    BorderRadius.circular(CommonUiShapes.pill),
                                border: Border.all(color: tokens.borderSubtle),
                              ),
                              child: Text(
                                mode.koreanName,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: tokens.textSecondary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: tokens.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkAreaViewData {
  const _WorkAreaViewData({
    required this.areaName,
    required this.isHeadquarter,
    required this.modes,
  });

  final String areaName;
  final bool isHeadquarter;
  final List<AppModeDefinition> modes;
}
