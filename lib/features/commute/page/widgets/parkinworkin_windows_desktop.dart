import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../launcher/application/launcher_diagnostics.dart';

enum ParkinWorkinDesktopStage {
  checking,
  ready,
  processing,
  success,
  failure,
}

enum ParkinWorkinStepStatus {
  waiting,
  checking,
  issue,
  reset,
  pending,
  ready,
  failure,
}

class ParkinWorkinApplicationField extends StatefulWidget {
  const ParkinWorkinApplicationField({
    super.key,
    required this.userName,
    required this.stage,
    required this.stateMessage,
    required this.enabled,
    required this.reduceMotion,
    required this.exiting,
    required this.modeKey,
    required this.onLaunch,
    required this.attendanceStatus,
    required this.workspaceStatus,
    this.embeddedPanel,
    this.consoleExtension,
  });

  static const Duration desktopRevealDuration = Duration(milliseconds: 560);
  static const Duration preFocusHoldDuration = Duration(milliseconds: 320);
  static const Duration selectionDuration = Duration(milliseconds: 120);
  static const Duration focusDuration = Duration(milliseconds: 620);
  static const Duration postFocusHoldDuration = Duration(milliseconds: 360);
  static const Duration startMessageDuration = Duration(milliseconds: 320);
  static const Duration appPressDuration = Duration(milliseconds: 180);
  static const Duration appLaunchDuration = Duration(milliseconds: 420);
  static const Duration fullscreenDuration = Duration(milliseconds: 430);

  final String userName;
  final ParkinWorkinDesktopStage stage;
  final String stateMessage;
  final bool enabled;
  final bool reduceMotion;
  final bool exiting;
  final String modeKey;
  final Future<void> Function() onLaunch;
  final ParkinWorkinStepStatus attendanceStatus;
  final ParkinWorkinStepStatus workspaceStatus;
  final Widget? embeddedPanel;
  final Widget? consoleExtension;

  @override
  State<ParkinWorkinApplicationField> createState() =>
      ParkinWorkinApplicationFieldState();
}

class ParkinWorkinApplicationFieldState
    extends State<ParkinWorkinApplicationField> with TickerProviderStateMixin {
  late final AnimationController _desktopController;
  late final AnimationController _selectionController;
  late final AnimationController _focusController;
  late final AnimationController _startMessageController;
  late final AnimationController _pressController;
  late final AnimationController _launchController;
  late final AnimationController _fullscreenController;
  bool _launched = false;
  bool _launchInFlight = false;
  bool _fullscreenInFlight = false;
  bool _startMessageVisibleLogged = false;
  bool _postFocusHoldComplete = false;
  String _sequencePhase = 'field';

  static const int _rowsPerColumn = 4;
  static const int _parkinWorkinIndex = 5;

  static const List<_ApplicationSpec> _applications = <_ApplicationSpec>[
    _ApplicationSpec('파일', Icons.folder_outlined),
    _ApplicationSpec('메일', Icons.mail_outline_rounded),
    _ApplicationSpec('문서', Icons.description_outlined),
    _ApplicationSpec('드라이브', Icons.storage_rounded),
    _ApplicationSpec('캘린더', Icons.calendar_month_outlined),
    _ApplicationSpec('ParkinWorkin', Icons.apps_rounded),
    _ApplicationSpec('노트', Icons.edit_note_rounded),
    _ApplicationSpec('메시지', Icons.forum_outlined),
    _ApplicationSpec('클라우드', Icons.cloud_outlined),
    _ApplicationSpec('설정', Icons.tune_rounded),
    _ApplicationSpec('보관함', Icons.inventory_2_outlined),
    _ApplicationSpec('도구', Icons.widgets_outlined),
  ];

  String get diagnosticPhase {
    if (_fullscreenInFlight || _fullscreenController.value > 0) {
      return _fullscreenController.value >= 1 ? 'fullscreen' : 'expanding';
    }
    if (_launchInFlight || _launchController.isAnimating) return 'launching';
    if (_launched) return 'application';
    return _sequencePhase;
  }

  bool get applicationLaunched => _launched;
  bool get applicationFocused => _focusController.value >= 0.999;
  bool get startMessageVisible => _startMessageController.value > 0.01 && !_launched;
  int get peripheralCount => _resolvePeripheralDirections().length;
  String get peripheralLayout => 'relative_eight_direction_neighbors';

  @override
  void initState() {
    super.initState();
    _desktopController = AnimationController(
      vsync: this,
      duration: ParkinWorkinApplicationField.desktopRevealDuration,
    );
    _selectionController = AnimationController(
      vsync: this,
      duration: ParkinWorkinApplicationField.selectionDuration,
    );
    _focusController = AnimationController(
      vsync: this,
      duration: ParkinWorkinApplicationField.focusDuration,
    );
    _startMessageController = AnimationController(
      vsync: this,
      duration: ParkinWorkinApplicationField.startMessageDuration,
    );
    _pressController = AnimationController(
      vsync: this,
      duration: ParkinWorkinApplicationField.appPressDuration,
    );
    _launchController = AnimationController(
      vsync: this,
      duration: ParkinWorkinApplicationField.appLaunchDuration,
    );
    _fullscreenController = AnimationController(
      vsync: this,
      duration: ParkinWorkinApplicationField.fullscreenDuration,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startApplicationFieldReveal());
    });
  }

  @override
  void didUpdateWidget(covariant ParkinWorkinApplicationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.attendanceStatus != widget.attendanceStatus ||
        oldWidget.workspaceStatus != widget.workspaceStatus ||
        (oldWidget.embeddedPanel == null) != (widget.embeddedPanel == null) ||
        (oldWidget.consoleExtension == null) !=
            (widget.consoleExtension == null)) {
      LauncherDiagnostics.record(
        'commute_application_field_state',
        scope: 'commute_application_field',
        meta: <String, Object?>{
          'mode': widget.modeKey,
          'stage': widget.stage.name,
          'enabled': widget.enabled,
          'embeddedPanel': widget.embeddedPanel != null,
          'consoleExtension': widget.consoleExtension != null,
          'attendanceStatus': widget.attendanceStatus.name,
          'workspaceStatus': widget.workspaceStatus.name,
          'focused': applicationFocused,
          'launched': _launched,
        },
      );
    }

    if (!_launched &&
        (widget.stage == ParkinWorkinDesktopStage.processing ||
            widget.stage == ParkinWorkinDesktopStage.success ||
            widget.embeddedPanel != null ||
            widget.consoleExtension != null)) {
      _launched = true;
      _startMessageController.value = 0;
      _selectionController.value = 1;
      _focusController.value = 1;
      _postFocusHoldComplete = true;
      _sequencePhase = 'application';
      if (widget.reduceMotion) {
        _launchController.value = 1;
      } else if (!_launchController.isAnimating) {
        unawaited(_launchController.forward(from: 0));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncStartMessageVisibility();
    });
  }

  Future<void> _startApplicationFieldReveal() async {
    _sequencePhase = 'field_reveal';
    LauncherDiagnostics.record(
      'commute_application_field_reveal_start',
      scope: 'commute_application_field',
      meta: <String, Object?>{
        'mode': widget.modeKey,
        'durationMs':
            ParkinWorkinApplicationField.desktopRevealDuration.inMilliseconds,
        'reduceMotion': widget.reduceMotion,
      },
    );
    if (widget.reduceMotion) {
      _desktopController.value = 1;
      _selectionController.value = 1;
      _focusController.value = 1;
      _postFocusHoldComplete = true;
      _sequencePhase = 'focused';
    } else {
      await _desktopController.forward(from: 0);
    }
    if (!mounted) return;
    LauncherDiagnostics.record(
      'commute_application_field_reveal_complete',
      scope: 'commute_application_field',
      meta: <String, Object?>{'mode': widget.modeKey},
    );
    if (widget.reduceMotion) {
      _syncStartMessageVisibility();
      return;
    }
    if (_launched) return;
    _sequencePhase = 'pre_focus_hold';
    LauncherDiagnostics.record(
      'commute_application_field_hold_start',
      scope: 'commute_application_field',
      meta: <String, Object?>{
        'mode': widget.modeKey,
        'durationMs':
            ParkinWorkinApplicationField.preFocusHoldDuration.inMilliseconds,
      },
    );
    await Future<void>.delayed(
      ParkinWorkinApplicationField.preFocusHoldDuration,
    );
    if (!mounted || _launched) return;
    LauncherDiagnostics.record(
      'commute_application_field_hold_complete',
      scope: 'commute_application_field',
      meta: <String, Object?>{'mode': widget.modeKey},
    );
    await _startSelection();
    if (!mounted || _launched) return;
    await _startFocus();
  }

  Future<void> _startSelection() async {
    if (!mounted || _launched || _selectionController.value >= 1) return;
    _sequencePhase = 'selecting';
    LauncherDiagnostics.record(
      'commute_parkinworkin_selection_start',
      scope: 'commute_application_field',
      meta: <String, Object?>{
        'mode': widget.modeKey,
        'durationMs':
            ParkinWorkinApplicationField.selectionDuration.inMilliseconds,
      },
    );
    await _selectionController.forward(from: 0);
    if (!mounted || _launched) return;
    LauncherDiagnostics.record(
      'commute_parkinworkin_selection_complete',
      scope: 'commute_application_field',
      meta: <String, Object?>{'mode': widget.modeKey},
    );
  }

  Future<void> _startFocus() async {
    if (!mounted || _launched || _focusController.value >= 1) return;
    final resolvedPeripheralCount = _resolvePeripheralDirections().length;
    _sequencePhase = 'focusing';
    LauncherDiagnostics.record(
      'commute_parkinworkin_focus_start',
      scope: 'commute_application_field',
      meta: <String, Object?>{
        'mode': widget.modeKey,
        'durationMs': ParkinWorkinApplicationField.focusDuration.inMilliseconds,
        'peripheralCount': resolvedPeripheralCount,
        'peripheralLayout': peripheralLayout,
        'cardinalBlur': 1.95,
        'diagonalBlur': 2.30,
      },
    );
    await _focusController.forward(from: 0);
    if (!mounted || _launched) return;
    LauncherDiagnostics.record(
      'commute_parkinworkin_focus_complete',
      scope: 'commute_application_field',
      meta: <String, Object?>{
        'mode': widget.modeKey,
        'peripheralCount': resolvedPeripheralCount,
        'peripheralLayout': peripheralLayout,
      },
    );
    _sequencePhase = 'post_focus_hold';
    LauncherDiagnostics.record(
      'commute_parkinworkin_focus_hold_start',
      scope: 'commute_application_field',
      meta: <String, Object?>{
        'mode': widget.modeKey,
        'durationMs':
            ParkinWorkinApplicationField.postFocusHoldDuration.inMilliseconds,
      },
    );
    await Future<void>.delayed(
      ParkinWorkinApplicationField.postFocusHoldDuration,
    );
    if (!mounted || _launched) return;
    _postFocusHoldComplete = true;
    _sequencePhase = 'focused';
    LauncherDiagnostics.record(
      'commute_parkinworkin_focus_hold_complete',
      scope: 'commute_application_field',
      meta: <String, Object?>{'mode': widget.modeKey},
    );
    _syncStartMessageVisibility();
  }

  void _syncStartMessageVisibility() {
    if (!mounted) return;
    final shouldShow = !_launched &&
        !widget.exiting &&
        widget.enabled &&
        _postFocusHoldComplete &&
        _focusController.value >= 0.999;

    if (shouldShow) {
      _sequencePhase = 'start_message';
      if (widget.reduceMotion) {
        _startMessageController.value = 1;
      } else if (!_startMessageController.isAnimating &&
          _startMessageController.value < 1) {
        unawaited(_startMessageController.forward());
      }
      if (!_startMessageVisibleLogged) {
        _startMessageVisibleLogged = true;
        LauncherDiagnostics.record(
          'commute_parkinworkin_start_message_visible',
          scope: 'commute_application_field',
          meta: <String, Object?>{
            'mode': widget.modeKey,
            'text': '오늘의 업무를 시작하시겠습니까?',
            'durationMs':
                ParkinWorkinApplicationField.startMessageDuration.inMilliseconds,
          },
        );
      }
      return;
    }

    _startMessageVisibleLogged = false;
    if (_postFocusHoldComplete && !_launched) {
      _sequencePhase = 'focused';
    }
    if (widget.reduceMotion) {
      _startMessageController.value = 0;
    } else if (!_startMessageController.isAnimating && _startMessageController.value > 0) {
      unawaited(_startMessageController.reverse());
    }
  }

  Map<int, _PeripheralDirection> _resolvePeripheralDirections() {
    final result = <int, _PeripheralDirection>{};
    final columnCount = (_applications.length / _rowsPerColumn).ceil();
    final parkinColumn = _parkinWorkinIndex ~/ _rowsPerColumn;
    final parkinRow = _parkinWorkinIndex % _rowsPerColumn;
    for (final direction in _PeripheralDirection.values) {
      final column = parkinColumn + direction.columnDelta;
      final row = parkinRow + direction.rowDelta;
      if (column < 0 || column >= columnCount || row < 0 || row >= _rowsPerColumn) {
        continue;
      }
      final index = (column * _rowsPerColumn) + row;
      if (index < 0 || index >= _applications.length || index == _parkinWorkinIndex) {
        continue;
      }
      result[index] = direction;
    }
    return result;
  }

  Future<void> _handleLaunch() async {
    if (!widget.enabled ||
        widget.exiting ||
        _launchInFlight ||
        _fullscreenInFlight ||
        _focusController.value < 0.999) {
      return;
    }

    _launchInFlight = true;
    await HapticFeedback.lightImpact();
    LauncherDiagnostics.record(
      'commute_parkinworkin_launch_start',
      scope: 'commute_application_field',
      meta: <String, Object?>{
        'mode': widget.modeKey,
        'pressMs': ParkinWorkinApplicationField.appPressDuration.inMilliseconds,
        'launchMs': ParkinWorkinApplicationField.appLaunchDuration.inMilliseconds,
        'retry': _launched,
      },
    );

    if (!_launched) {
      if (widget.reduceMotion) {
        _pressController.value = 1;
        _startMessageController.value = 0;
      } else {
        unawaited(_startMessageController.reverse());
        await _pressController.forward(from: 0);
      }
      if (!mounted) return;
      setState(() => _launched = true);
      if (widget.reduceMotion) {
        _launchController.value = 1;
      } else {
        unawaited(_launchController.forward(from: 0));
      }
    }

    try {
      await widget.onLaunch();
    } finally {
      if (mounted) {
        _launchInFlight = false;
      }
    }

    if (!mounted) return;
    LauncherDiagnostics.record(
      'commute_parkinworkin_launch_complete',
      scope: 'commute_application_field',
      meta: <String, Object?>{
        'mode': widget.modeKey,
        'stage': widget.stage.name,
      },
    );
  }

  Future<void> expandToFullscreen() async {
    if (_fullscreenInFlight || !mounted) return;
    _fullscreenInFlight = true;
    _startMessageController.value = 0;
    _focusController.value = 1;
    if (!_launched) {
      setState(() => _launched = true);
      _launchController.value = 1;
    }
    LauncherDiagnostics.record(
      'commute_application_fullscreen_start',
      scope: 'commute_application_field',
      meta: <String, Object?>{
        'mode': widget.modeKey,
        'durationMs':
            ParkinWorkinApplicationField.fullscreenDuration.inMilliseconds,
        'reduceMotion': widget.reduceMotion,
      },
    );
    if (widget.reduceMotion) {
      _fullscreenController.value = 1;
    } else {
      await _fullscreenController.forward(from: 0);
    }
    if (!mounted) return;
    LauncherDiagnostics.record(
      'commute_application_fullscreen_complete',
      scope: 'commute_application_field',
      meta: <String, Object?>{'mode': widget.modeKey},
    );
  }

  @override
  void dispose() {
    _desktopController.dispose();
    _selectionController.dispose();
    _focusController.dispose();
    _startMessageController.dispose();
    _pressController.dispose();
    _launchController.dispose();
    _fullscreenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
        final sceneHeight = keyboardVisible
            ? math.max(120.0, height - 12).toDouble()
            : math.max(220.0, height - 72).toDouble();
        final horizontalPadding = width < 390 ? 14.0 : 22.0;
        final columnCount =
            (_applications.length / _rowsPerColumn).ceil().clamp(1, 8);
        final columnSlot =
            math.max(76.0, (width - (horizontalPadding * 2)) / columnCount)
                .toDouble();
        final rowSlot = math
            .max(64.0, (sceneHeight - 34) / _rowsPerColumn)
            .toDouble();
        final tileWidth = math.min(94.0, columnSlot - 8).toDouble();
        final tileHeight = math.min(96.0, rowSlot - 4).toDouble();

        Rect gridRectFor(int index) {
          final column = index ~/ _rowsPerColumn;
          final row = index % _rowsPerColumn;
          final left = horizontalPadding +
              (column * columnSlot) +
              ((columnSlot - tileWidth) / 2);
          final top = 14 +
              (row * rowSlot) +
              math.max(0.0, (rowSlot - tileHeight) / 2);
          return Rect.fromLTWH(left, top, tileWidth, tileHeight);
        }

        final initialParkinRect = gridRectFor(_parkinWorkinIndex);
        final focusWidth = math.min(172.0, math.max(142.0, width * 0.39)).toDouble();
        final focusHeight = focusWidth + 18;
        final focusCenterY = math.min(
          sceneHeight * 0.46,
          math.max(focusHeight / 2 + 40, sceneHeight * 0.42),
        );
        final focusRect = Rect.fromCenter(
          center: Offset(width / 2, focusCenterY),
          width: focusWidth,
          height: focusHeight,
        );
        final applicationWidth =
            math.min(600.0, math.max(286.0, width - 34)).toDouble();
        final maxApplicationHeight = keyboardVisible
            ? math.max(120.0, sceneHeight - 6).toDouble()
            : math.max(280.0, sceneHeight - 20).toDouble();
        final applicationHeight = math
            .min(560.0, maxApplicationHeight)
            .toDouble();
        final applicationRect = Rect.fromLTWH(
          (width - applicationWidth) / 2,
          math
              .max(
                keyboardVisible ? 3.0 : 10.0,
                (sceneHeight - applicationHeight) / 2,
              )
              .toDouble(),
          applicationWidth,
          applicationHeight,
        );
        final fullscreenRect = Rect.fromLTWH(0, 0, width, height);
        final peripheralTargets = _buildPeripheralTargets(
          width: width,
          sceneHeight: sceneHeight,
          tileWidth: tileWidth,
          tileHeight: tileHeight,
          focusRect: focusRect,
        );
        final maxPeripheralCenterY = peripheralTargets.values.isEmpty
            ? focusRect.bottom
            : peripheralTargets.values
                .map((target) => target.rect.center.dy)
                .reduce(math.max);
        final messageTop = math
            .min(
              sceneHeight - 58,
              math.max(
                focusRect.bottom + 28,
                maxPeripheralCenterY + (tileHeight * 0.24) + 22,
              ),
            )
            .toDouble();

        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _desktopController,
            _selectionController,
            _focusController,
            _startMessageController,
            _pressController,
            _launchController,
            _fullscreenController,
          ]),
          builder: (context, child) {
            final desktopValue = widget.reduceMotion
                ? 1.0
                : Curves.easeOutCubic.transform(_desktopController.value);
            final selectionValue = widget.reduceMotion
                ? (_selectionController.value > 0 ? 1.0 : 0.0)
                : Curves.easeOutCubic.transform(_selectionController.value);
            final rawFocusValue = widget.reduceMotion
                ? (_focusController.value > 0 ? 1.0 : 0.0)
                : _focusController.value;
            final focusValue = widget.reduceMotion
                ? rawFocusValue
                : Curves.easeInOutCubic.transform(rawFocusValue);
            final messageValue = widget.reduceMotion
                ? (_startMessageController.value > 0 ? 1.0 : 0.0)
                : Curves.easeOutCubic.transform(_startMessageController.value);
            final pressScale = widget.reduceMotion
                ? 1.0
                : 1 - (0.045 * math.sin(_pressController.value * math.pi));
            final launchValue = widget.reduceMotion
                ? (_launched ? 1.0 : 0.0)
                : Curves.easeOutCubic.transform(_launchController.value);
            final fullscreenValue = widget.reduceMotion
                ? (_fullscreenController.value > 0 ? 1.0 : 0.0)
                : Curves.easeInOutCubic.transform(_fullscreenController.value);
            final fieldOpacity =
                (1 - fullscreenValue).clamp(0.0, 1.0).toDouble();
            final launchTarget =
                Rect.lerp(applicationRect, fullscreenRect, fullscreenValue)!;
            final foregroundRect = _launched
                ? Rect.lerp(focusRect, launchTarget, launchValue)!
                : Rect.lerp(initialParkinRect, focusRect, focusValue)!;
            final applicationContentOpacity = _launched
                ? ((launchValue - 0.20) / 0.80).clamp(0.0, 1.0).toDouble()
                : 0.0;
            final focusedContentOpacity = _launched
                ? (1 - (launchValue / 0.45).clamp(0.0, 1.0)).toDouble()
                : 1.0;
            final borderRadius = _launched
                ? ui.lerpDouble(24, 18, launchValue)! * (1 - fullscreenValue)
                : ui.lerpDouble(18, 28, focusValue)!;

            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ApplicationFieldBackground(
                    tokens: tokens,
                    opacity: fieldOpacity,
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    height: sceneHeight,
                    child: ClipRect(
                      child: Opacity(
                        opacity: fieldOpacity,
                        child: Stack(
                          children: [
                            for (var index = 0;
                                index < _applications.length;
                                index++)
                              if (index != _parkinWorkinIndex)
                                _buildBackgroundApplication(
                                  index: index,
                                  gridRect: gridRectFor(index),
                                  peripheralTargets: peripheralTargets,
                                  desktopValue: desktopValue,
                                  rawFocusValue: rawFocusValue,
                                  focusValue: focusValue,
                                  launchValue: launchValue,
                                  tokens: tokens,
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: foregroundRect,
                    child: Transform.scale(
                      scale: _launched
                          ? 1
                          : pressScale *
                              (1 +
                                  (0.04 *
                                      selectionValue *
                                      (1 - focusValue))),
                      child: _launched
                          ? _BrandedApplicationSurface(
                              tokens: tokens,
                              stage: widget.stage,
                              stateMessage: widget.stateMessage,
                              enabled: widget.enabled,
                              reduceMotion: widget.reduceMotion,
                              embeddedPanel: widget.embeddedPanel,
                              consoleExtension: widget.consoleExtension,
                              attendanceStatus: widget.attendanceStatus,
                              workspaceStatus: widget.workspaceStatus,
                              contentOpacity: applicationContentOpacity,
                              borderRadius: borderRadius,
                              onRetry: _handleLaunch,
                            )
                          : Semantics(
                              button: widget.enabled && focusValue >= 0.999,
                              enabled: widget.enabled && focusValue >= 0.999,
                              label: '오늘의 업무 시작',
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(borderRadius),
                                  onTap: widget.enabled &&
                                          focusValue >= 0.999 &&
                                          !widget.exiting
                                      ? () => unawaited(_handleLaunch())
                                      : null,
                                  child: Opacity(
                                    opacity: focusedContentOpacity,
                                    child: _ParkinWorkinFocusTile(
                                      tokens: tokens,
                                      focusValue: focusValue,
                                      selectionValue: selectionValue,
                                      stage: widget.stage,
                                      enabled: widget.enabled,
                                      borderRadius: borderRadius,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (!_launched)
                    Positioned(
                      left: 20,
                      right: 20,
                      top: messageTop,
                      child: IgnorePointer(
                        child: _StartMessage(
                          tokens: tokens,
                          opacity: messageValue,
                          checking: widget.stage ==
                              ParkinWorkinDesktopStage.checking,
                          focused: focusValue >= 0.999,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBackgroundApplication({
    required int index,
    required Rect gridRect,
    required Map<int, _PeripheralTarget> peripheralTargets,
    required double desktopValue,
    required double rawFocusValue,
    required double focusValue,
    required double launchValue,
    required CommonUiTokens tokens,
  }) {
    final application = _applications[index];
    final revealStart = math.min(0.54, index * 0.045).toDouble();
    final reveal = ((desktopValue - revealStart) / (1 - revealStart))
        .clamp(0.0, 1.0)
        .toDouble();
    final target = peripheralTargets[index];
    final isPeripheral = target != null;
    final isDiagonal = target?.direction.isDiagonal ?? false;
    final movementValue = isPeripheral
        ? _interval(
            rawFocusValue,
            isDiagonal ? 0.13 : 0.08,
            isDiagonal ? 0.90 : 0.94,
          )
        : focusValue;
    final targetRect = target?.rect ?? gridRect;
    final rect = Rect.lerp(gridRect, targetRect, movementValue)!;
    final focusedBlur = isDiagonal ? 2.30 : 1.95;
    final blur = isPeripheral
        ? ui.lerpDouble(0.45, focusedBlur, movementValue)!
        : ui.lerpDouble(0.45, 2.8, focusValue)!;
    final focusedOpacity = isPeripheral ? (isDiagonal ? 0.40 : 0.53) : 0.0;
    final opacity = reveal *
        ui.lerpDouble(0.76, focusedOpacity, movementValue)! *
        ui.lerpDouble(1, 0.58, launchValue)!;
    final focusedScale = isDiagonal ? 0.88 : 0.93;
    final scale = ui.lerpDouble(0.97, isPeripheral ? focusedScale : 0.90, movementValue)!;
    final tile = _ApplicationTile(
      tokens: tokens,
      application: application,
    );

    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0).toDouble(),
            child: Transform.translate(
              offset: Offset(0, 7 * (1 - reveal)),
              child: Transform.scale(
                scale: scale,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: blur,
                    sigmaY: blur,
                  ),
                  child: isPeripheral
                      ? ClipRect(
                          clipper: _PeripheralClipper(
                            direction: target.direction,
                            progress: movementValue,
                          ),
                          child: tile,
                        )
                      : tile,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _interval(
    double value,
    double start,
    double end,
  ) {
    final normalized = ((value - start) / (end - start))
        .clamp(0.0, 1.0)
        .toDouble();
    return Curves.easeInOutCubic.transform(normalized);
  }

  Map<int, _PeripheralTarget> _buildPeripheralTargets({
    required double width,
    required double sceneHeight,
    required double tileWidth,
    required double tileHeight,
    required Rect focusRect,
  }) {
    final directions = _resolvePeripheralDirections();
    final center = focusRect.center;
    final cardinalX = math
        .max(
          focusRect.width / 2 + (tileWidth * 0.34) + 18,
          width * 0.32,
        )
        .toDouble();
    final cardinalY = math
        .max(
          focusRect.height / 2 + (tileHeight * 0.34) + 24,
          sceneHeight * 0.24,
        )
        .toDouble();
    final diagonalX = math
        .max(
          focusRect.width / 2 + (tileWidth * 0.26) + 16,
          width * 0.29,
        )
        .toDouble();
    final diagonalY = math
        .max(
          focusRect.height / 2 + (tileHeight * 0.26) + 16,
          sceneHeight * 0.22,
        )
        .toDouble();
    final result = <int, _PeripheralTarget>{};

    for (final entry in directions.entries) {
      final direction = entry.value;
      final dx = direction.columnDelta == 0
          ? 0.0
          : direction.columnDelta *
              (direction.isDiagonal ? diagonalX : cardinalX);
      final dy = direction.rowDelta == 0
          ? 0.0
          : direction.rowDelta *
              (direction.isDiagonal ? diagonalY : cardinalY);
      result[entry.key] = _PeripheralTarget(
        rect: Rect.fromCenter(
          center: center + Offset(dx, dy),
          width: tileWidth,
          height: tileHeight,
        ),
        direction: direction,
      );
    }

    return result;
  }

}

class _PeripheralDirection {
  const _PeripheralDirection(
    this.name,
    this.columnDelta,
    this.rowDelta,
  );

  final String name;
  final int columnDelta;
  final int rowDelta;

  bool get isDiagonal => columnDelta != 0 && rowDelta != 0;

  static const topLeft = _PeripheralDirection('top_left', -1, -1);
  static const top = _PeripheralDirection('top', 0, -1);
  static const topRight = _PeripheralDirection('top_right', 1, -1);
  static const left = _PeripheralDirection('left', -1, 0);
  static const right = _PeripheralDirection('right', 1, 0);
  static const bottomLeft = _PeripheralDirection('bottom_left', -1, 1);
  static const bottom = _PeripheralDirection('bottom', 0, 1);
  static const bottomRight = _PeripheralDirection('bottom_right', 1, 1);

  static const values = <_PeripheralDirection>[
    topLeft,
    top,
    topRight,
    left,
    right,
    bottomLeft,
    bottom,
    bottomRight,
  ];
}

class _PeripheralTarget {
  const _PeripheralTarget({
    required this.rect,
    required this.direction,
  });

  final Rect rect;
  final _PeripheralDirection direction;
}

class _PeripheralClipper extends CustomClipper<Rect> {
  const _PeripheralClipper({
    required this.direction,
    required this.progress,
  });

  final _PeripheralDirection direction;
  final double progress;

  @override
  Rect getClip(Size size) {
    final targetFraction = direction.isDiagonal ? 0.72 : 0.68;
    final fraction = ui.lerpDouble(1, targetFraction, progress)!;
    final horizontalFraction = direction.columnDelta == 0 ? 1.0 : fraction;
    final verticalFraction = direction.rowDelta == 0 ? 1.0 : fraction;
    final visibleWidth = size.width * horizontalFraction;
    final visibleHeight = size.height * verticalFraction;
    final left = direction.columnDelta < 0
        ? size.width - visibleWidth
        : 0.0;
    final top = direction.rowDelta < 0
        ? size.height - visibleHeight
        : 0.0;
    return Rect.fromLTWH(left, top, visibleWidth, visibleHeight);
  }

  @override
  bool shouldReclip(covariant _PeripheralClipper oldClipper) {
    return oldClipper.direction != direction || oldClipper.progress != progress;
  }
}

class _ApplicationFieldBackground extends StatelessWidget {
  const _ApplicationFieldBackground({
    required this.tokens,
    required this.opacity,
  });

  final CommonUiTokens tokens;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              tokens.canvas,
              Color.lerp(tokens.canvas, tokens.surface, 0.58)!,
              tokens.canvas,
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplicationSpec {
  const _ApplicationSpec(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _ApplicationTile extends StatelessWidget {
  const _ApplicationTile({
    required this.tokens,
    required this.application,
  });

  final CommonUiTokens tokens;
  final _ApplicationSpec application;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = math
            .min(52.0, math.min(constraints.maxWidth * 0.54, constraints.maxHeight * 0.52))
            .toDouble();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.surfaceRaised.withOpacity(0.70),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Icon(
                application.icon,
                size: iconSize * 0.50,
                color: tokens.iconSecondary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              application.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _ParkinWorkinFocusTile extends StatelessWidget {
  const _ParkinWorkinFocusTile({
    required this.tokens,
    required this.focusValue,
    required this.selectionValue,
    required this.stage,
    required this.enabled,
    required this.borderRadius,
  });

  final CommonUiTokens tokens;
  final double focusValue;
  final double selectionValue;
  final ParkinWorkinDesktopStage stage;
  final bool enabled;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final checking = stage == ParkinWorkinDesktopStage.checking;
    final emphasis = math.max(focusValue, selectionValue).toDouble();
    final glowOpacity = ui.lerpDouble(0.10, enabled ? 0.28 : 0.16, emphasis)!;
    final iconSize = ui.lerpDouble(46, 82, focusValue)!;
    final labelScale = ui.lerpDouble(0.92, 1.0, focusValue)!;
    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(
          tokens.surfaceRaised.withOpacity(0.50),
          tokens.surfaceRaised.withOpacity(0.92),
          emphasis,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: enabled
              ? tokens.accent.withOpacity(ui.lerpDouble(0.24, 0.72, emphasis)!)
              : tokens.borderStrong,
          width: emphasis > 0.78 ? 1.4 : 1,
        ),
        boxShadow: emphasis > 0.20
            ? <BoxShadow>[
                BoxShadow(
                  color: tokens.accent.withOpacity(glowOpacity),
                  blurRadius: ui.lerpDouble(10, 30, emphasis)!,
                  spreadRadius: ui.lerpDouble(0, 2, emphasis)!,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: Image.asset(
                    'assets/images/ParkinWorkin_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                SizedBox(height: ui.lerpDouble(7, 12, focusValue)!),
                Transform.scale(
                  scale: labelScale,
                  child: Text(
                    'ParkinWorkin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (checking && focusValue >= 0.92)
            Positioned(
              right: 14,
              bottom: 14,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: tokens.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StartMessage extends StatelessWidget {
  const _StartMessage({
    required this.tokens,
    required this.opacity,
    required this.checking,
    required this.focused,
  });

  final CommonUiTokens tokens;
  final double opacity;
  final bool checking;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    if (!focused) return const SizedBox.shrink();
    if (checking && opacity <= 0) {
      return const SizedBox(height: 30);
    }
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - opacity)),
        child: Transform.scale(
          scale: ui.lerpDouble(0.985, 1, opacity)!,
          child: Text(
            '오늘의 업무를 시작하시겠습니까?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                  letterSpacing: ui.lerpDouble(0.5, 0.0, opacity)!,
                ),
          ),
        ),
      ),
    );
  }
}

class _BrandedApplicationSurface extends StatelessWidget {
  const _BrandedApplicationSurface({
    required this.tokens,
    required this.stage,
    required this.stateMessage,
    required this.enabled,
    required this.reduceMotion,
    required this.embeddedPanel,
    required this.consoleExtension,
    required this.attendanceStatus,
    required this.workspaceStatus,
    required this.contentOpacity,
    required this.borderRadius,
    required this.onRetry,
  });

  final CommonUiTokens tokens;
  final ParkinWorkinDesktopStage stage;
  final String stateMessage;
  final bool enabled;
  final bool reduceMotion;
  final Widget? embeddedPanel;
  final Widget? consoleExtension;
  final ParkinWorkinStepStatus attendanceStatus;
  final ParkinWorkinStepStatus workspaceStatus;
  final double contentOpacity;
  final double borderRadius;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final statusColor = _applicationStatusColor(
      tokens,
      stage: stage,
      attendanceStatus: attendanceStatus,
      workspaceStatus: workspaceStatus,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          border: Border.all(color: tokens.borderStrong),
          boxShadow: borderRadius > 0
              ? <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(tokens.isDark ? 0.26 : 0.10),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Opacity(
          opacity: contentOpacity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BrandHeader(tokens: tokens, statusColor: statusColor),
              Expanded(
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.component,
                  reverseDuration:
                      reduceMotion ? Duration.zero : CommonUiMotion.component,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  transitionBuilder: (child, animation) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: CommonUiMotion.enter,
                      reverseCurve: CommonUiMotion.exit,
                    );
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.035),
                      end: Offset.zero,
                    ).animate(curved);
                    final scale =
                        Tween<double>(begin: 0.985, end: 1).animate(curved);
                    return FadeTransition(
                      opacity: curved,
                      child: SlideTransition(
                        position: slide,
                        child: ScaleTransition(scale: scale, child: child),
                      ),
                    );
                  },
                  child: embeddedPanel != null
                      ? KeyedSubtree(
                          key: embeddedPanel!.key ??
                              ValueKey<Type>(embeddedPanel.runtimeType),
                          child: embeddedPanel!,
                        )
                      : _ApplicationStatusBody(
                          key: const ValueKey<String>('application_status'),
                          tokens: tokens,
                          stage: stage,
                          stateMessage: stateMessage,
                          statusColor: statusColor,
                          enabled: enabled,
                          reduceMotion: reduceMotion,
                          attendanceStatus: attendanceStatus,
                          workspaceStatus: workspaceStatus,
                          consoleExtension: consoleExtension,
                          onRetry: onRetry,
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

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.tokens,
    required this.statusColor,
  });

  final CommonUiTokens tokens;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(
          bottom: BorderSide(color: tokens.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Image.asset(
              'assets/images/ParkinWorkin_logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ParkinWorkin',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

Color _applicationStatusColor(
  CommonUiTokens tokens, {
  required ParkinWorkinDesktopStage stage,
  required ParkinWorkinStepStatus attendanceStatus,
  required ParkinWorkinStepStatus workspaceStatus,
}) {
  if (attendanceStatus == ParkinWorkinStepStatus.failure ||
      stage == ParkinWorkinDesktopStage.failure) {
    return tokens.danger;
  }
  if (attendanceStatus == ParkinWorkinStepStatus.issue ||
      workspaceStatus == ParkinWorkinStepStatus.pending) {
    return tokens.warning;
  }
  if (attendanceStatus == ParkinWorkinStepStatus.checking ||
      workspaceStatus == ParkinWorkinStepStatus.checking ||
      stage == ParkinWorkinDesktopStage.processing ||
      stage == ParkinWorkinDesktopStage.checking) {
    return tokens.brandPrimary;
  }
  if (attendanceStatus == ParkinWorkinStepStatus.reset ||
      workspaceStatus == ParkinWorkinStepStatus.ready ||
      stage == ParkinWorkinDesktopStage.success) {
    return tokens.success;
  }
  return tokens.brandPrimary;
}

class _ApplicationStatusBody extends StatelessWidget {
  const _ApplicationStatusBody({
    super.key,
    required this.tokens,
    required this.stage,
    required this.stateMessage,
    required this.statusColor,
    required this.enabled,
    required this.reduceMotion,
    required this.attendanceStatus,
    required this.workspaceStatus,
    required this.consoleExtension,
    required this.onRetry,
  });

  final CommonUiTokens tokens;
  final ParkinWorkinDesktopStage stage;
  final String stateMessage;
  final Color statusColor;
  final bool enabled;
  final bool reduceMotion;
  final ParkinWorkinStepStatus attendanceStatus;
  final ParkinWorkinStepStatus workspaceStatus;
  final Widget? consoleExtension;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.component;
    final title = stateMessage.isNotEmpty
        ? stateMessage
        : switch (stage) {
            ParkinWorkinDesktopStage.checking =>
              'ParkinWorkin 실행 환경을 확인하고 있습니다.',
            ParkinWorkinDesktopStage.ready => '오늘의 업무를 시작할 준비가 되었습니다.',
            ParkinWorkinDesktopStage.processing => '근무 환경을 확인하고 있습니다.',
            ParkinWorkinDesktopStage.success => '근무 환경 준비가 완료되었습니다.',
            ParkinWorkinDesktopStage.failure => '근무 환경을 준비하지 못했습니다.',
          };
    final checking = stage == ParkinWorkinDesktopStage.checking ||
        stage == ParkinWorkinDesktopStage.processing ||
        attendanceStatus == ParkinWorkinStepStatus.checking ||
        workspaceStatus == ParkinWorkinStepStatus.checking;
    final failure = stage == ParkinWorkinDesktopStage.failure ||
        attendanceStatus == ParkinWorkinStepStatus.failure;
    final success = stage == ParkinWorkinDesktopStage.success &&
        workspaceStatus == ParkinWorkinStepStatus.ready;
    final icon = _statusIcon(
      checking: checking,
      failure: failure,
      success: success,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedSwitcher(
                duration: duration,
                child: checking
                    ? SizedBox(
                        key: const ValueKey<String>('application_checking'),
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: statusColor,
                        ),
                      )
                    : Icon(
                        icon,
                        key: ValueKey<String>(
                          '${attendanceStatus.name}_${workspaceStatus.name}_${stage.name}',
                        ),
                        color: statusColor,
                        size: 26,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  transitionBuilder: (child, animation) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: CommonUiMotion.enter,
                      reverseCurve: CommonUiMotion.exit,
                    );
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.035),
                      end: Offset.zero,
                    ).animate(curved);
                    return FadeTransition(
                      opacity: curved,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: Text(
                    title,
                    key: ValueKey<String>(title),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ApplicationStatusRow(
                    tokens: tokens,
                    label: 'SESSION',
                    status: ParkinWorkinStepStatus.ready,
                    reduceMotion: reduceMotion,
                  ),
                  const SizedBox(height: 9),
                  _ApplicationStatusRow(
                    tokens: tokens,
                    label: 'WORK AREA',
                    status: ParkinWorkinStepStatus.ready,
                    reduceMotion: reduceMotion,
                  ),
                  const SizedBox(height: 9),
                  _ApplicationStatusRow(
                    tokens: tokens,
                    label: 'ATTENDANCE',
                    status: attendanceStatus,
                    reduceMotion: reduceMotion,
                  ),
                  const SizedBox(height: 9),
                  _ApplicationStatusRow(
                    tokens: tokens,
                    label: 'WORKSPACE',
                    status: workspaceStatus,
                    reduceMotion: reduceMotion,
                  ),
                  AnimatedSize(
                    duration: duration,
                    curve: CommonUiMotion.standard,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: duration,
                      reverseDuration: duration,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      transitionBuilder: (child, animation) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: CommonUiMotion.enter,
                          reverseCurve: CommonUiMotion.exit,
                        );
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.025),
                          end: Offset.zero,
                        ).animate(curved);
                        return FadeTransition(
                          opacity: curved,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      child: consoleExtension == null
                          ? const SizedBox.shrink(
                              key: ValueKey<String>('console_extension_hidden'),
                            )
                          : Padding(
                              key: consoleExtension!.key ??
                                  ValueKey<Type>(consoleExtension!.runtimeType),
                              padding: const EdgeInsets.only(top: 14),
                              child: consoleExtension!,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: duration,
            curve: CommonUiMotion.standard,
            height: 3,
            decoration: BoxDecoration(
              color: tokens.borderSubtle,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              duration: duration,
              curve: CommonUiMotion.standard,
              tween: Tween<double>(
                begin: 0,
                end: _progressFactor(
                  stage: stage,
                  attendanceStatus: attendanceStatus,
                  workspaceStatus: workspaceStatus,
                ),
              ),
              builder: (context, value, child) {
                return FractionallySizedBox(
                  heightFactor: 1,
                  widthFactor: value,
                  alignment: Alignment.centerLeft,
                  child: child,
                );
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          if (consoleExtension == null &&
              (failure || stage == ParkinWorkinDesktopStage.ready) &&
              enabled) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => unawaited(onRetry()),
                icon: Icon(
                  failure || stateMessage.isNotEmpty
                      ? Icons.refresh_rounded
                      : Icons.play_arrow_rounded,
                  size: 18,
                ),
                label: Text(
                  failure || stateMessage.isNotEmpty ? '다시 확인' : '업무 시작',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _statusIcon({
    required bool checking,
    required bool failure,
    required bool success,
  }) {
    if (failure) return Icons.error_outline_rounded;
    if (attendanceStatus == ParkinWorkinStepStatus.issue) {
      return Icons.warning_amber_rounded;
    }
    if (attendanceStatus == ParkinWorkinStepStatus.reset) {
      return Icons.restart_alt_rounded;
    }
    if (workspaceStatus == ParkinWorkinStepStatus.pending) {
      return Icons.schedule_rounded;
    }
    if (success) return Icons.check_circle_rounded;
    if (checking) return Icons.sync_rounded;
    return Icons.apps_rounded;
  }
}

double _progressFactor({
  required ParkinWorkinDesktopStage stage,
  required ParkinWorkinStepStatus attendanceStatus,
  required ParkinWorkinStepStatus workspaceStatus,
}) {
  if (workspaceStatus == ParkinWorkinStepStatus.ready &&
      stage == ParkinWorkinDesktopStage.success) {
    return 1;
  }
  if (workspaceStatus == ParkinWorkinStepStatus.checking) return 0.94;
  if (workspaceStatus == ParkinWorkinStepStatus.pending) return 0.90;
  if (attendanceStatus == ParkinWorkinStepStatus.reset) return 0.42;
  if (attendanceStatus == ParkinWorkinStepStatus.checking &&
      stage == ParkinWorkinDesktopStage.ready) {
    return 0.66;
  }
  if (attendanceStatus == ParkinWorkinStepStatus.issue) return 0.55;
  if (attendanceStatus == ParkinWorkinStepStatus.failure ||
      stage == ParkinWorkinDesktopStage.failure) {
    return 0.58;
  }
  if (stage == ParkinWorkinDesktopStage.processing) return 0.76;
  if (stage == ParkinWorkinDesktopStage.checking) return 0.22;
  if (stage == ParkinWorkinDesktopStage.success) return 0.82;
  return 0.34;
}

class ParkinWorkinConsoleRow extends StatelessWidget {
  const ParkinWorkinConsoleRow({
    super.key,
    required this.label,
    required this.reduceMotion,
    this.value,
    this.child,
    this.valueColor,
    this.valueFontWeight = FontWeight.w700,
    this.trailing,
  }) : assert((value == null) != (child == null));

  final String label;
  final bool reduceMotion;
  final String? value;
  final Widget? child;
  final Color? valueColor;
  final FontWeight valueFontWeight;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final resolvedValueColor = valueColor ?? tokens.textPrimary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 94,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
          ),
        ),
        Expanded(
          child: child ??
              AnimatedSwitcher(
                duration: duration,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: CommonUiMotion.enter,
                    reverseCurve: CommonUiMotion.exit,
                  );
                  final slide = Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(curved);
                  return FadeTransition(
                    opacity: curved,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: Text(
                  value ?? '',
                  key: ValueKey<String>(value ?? ''),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: resolvedValueColor,
                        fontWeight: valueFontWeight,
                        height: 1.35,
                      ),
                ),
              ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

class ParkinWorkinConsoleAction extends StatefulWidget {
  const ParkinWorkinConsoleAction({
    super.key,
    required this.reduceMotion,
    required this.attentionToken,
    required this.child,
    this.attentionEnabled = true,
  });

  final bool reduceMotion;
  final Object attentionToken;
  final bool attentionEnabled;
  final Widget child;

  @override
  State<ParkinWorkinConsoleAction> createState() =>
      _ParkinWorkinConsoleActionState();
}

class _ParkinWorkinConsoleActionState extends State<ParkinWorkinConsoleAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
      value: widget.reduceMotion || !widget.attentionEnabled ? 1 : 0,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playAttention();
    });
  }

  @override
  void didUpdateWidget(covariant ParkinWorkinConsoleAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _controller
        ..stop()
        ..value = 1;
      return;
    }
    final shouldReplay = widget.attentionEnabled &&
        (!oldWidget.attentionEnabled ||
            oldWidget.attentionToken != widget.attentionToken ||
            oldWidget.reduceMotion != widget.reduceMotion);
    if (shouldReplay) _playAttention();
  }

  void _playAttention() {
    LauncherDiagnostics.record(
      'commute_console_action_attention',
      scope: 'commute_application_field',
      meta: <String, Object?>{
        'token': widget.attentionToken.toString(),
        'enabled': widget.attentionEnabled,
        'reduceMotion': widget.reduceMotion,
        'durationMs': widget.reduceMotion || !widget.attentionEnabled
            ? 0
            : _controller.duration?.inMilliseconds ?? 0,
      },
    );
    if (widget.reduceMotion || !widget.attentionEnabled) {
      _controller.value = 1;
      return;
    }
    _controller
      ..stop()
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);

    return ParkinWorkinConsoleRow(
      label: 'ACTION',
      reduceMotion: widget.reduceMotion,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          if (widget.reduceMotion || !widget.attentionEnabled) return child!;
          final value = _controller.value;
          final enter = Curves.easeOutCubic.transform(
            (value / 0.34).clamp(0.0, 1.0).toDouble(),
          );
          final lineGrow = Curves.easeOutCubic.transform(
            (value / 0.70).clamp(0.0, 1.0).toDouble(),
          );
          final lineOpacity = value <= 0.70
              ? (0.24 + value * 0.76).clamp(0.0, 1.0).toDouble()
              : ((1 - value) / 0.30).clamp(0.0, 1.0).toDouble();
          final emphasis = math.sin(math.pi * value).clamp(0.0, 1.0).toDouble();

          return Opacity(
            opacity: 0.58 + (0.42 * enter),
            child: Transform.translate(
              offset: Offset((1 - enter) * 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  child!,
                  SizedBox(
                    height: 2,
                    child: Opacity(
                      opacity: lineOpacity,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FractionallySizedBox(
                          widthFactor: lineGrow,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.brandPrimary.withOpacity(
                                0.45 + (0.45 * emphasis),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ApplicationStatusRow extends StatelessWidget {
  const _ApplicationStatusRow({
    required this.tokens,
    required this.label,
    required this.status,
    required this.reduceMotion,
  });

  final CommonUiTokens tokens;
  final String label;
  final ParkinWorkinStepStatus status;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return ParkinWorkinConsoleRow(
      label: label,
      value: _statusLabel(status),
      reduceMotion: reduceMotion,
      valueColor: _statusColor(tokens, status),
    );
  }
}

Color _statusColor(
  CommonUiTokens tokens,
  ParkinWorkinStepStatus status,
) {
  return switch (status) {
    ParkinWorkinStepStatus.waiting => tokens.textSecondary,
    ParkinWorkinStepStatus.checking => tokens.brandPrimary,
    ParkinWorkinStepStatus.issue => tokens.warning,
    ParkinWorkinStepStatus.reset => tokens.success,
    ParkinWorkinStepStatus.pending => tokens.warning,
    ParkinWorkinStepStatus.ready => tokens.success,
    ParkinWorkinStepStatus.failure => tokens.danger,
  };
}

String _statusLabel(ParkinWorkinStepStatus status) {
  return switch (status) {
    ParkinWorkinStepStatus.waiting => 'WAITING',
    ParkinWorkinStepStatus.checking => 'CHECKING',
    ParkinWorkinStepStatus.issue => 'ISSUE',
    ParkinWorkinStepStatus.reset => 'RESET',
    ParkinWorkinStepStatus.pending => 'PENDING',
    ParkinWorkinStepStatus.ready => 'READY',
    ParkinWorkinStepStatus.failure => 'RETRY',
  };
}
