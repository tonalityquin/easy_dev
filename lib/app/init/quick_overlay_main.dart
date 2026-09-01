import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/overlay_edge_side_config.dart';
import 'checkout_nudge_guard.dart';
import 'overlay_access_guard.dart';

const Color kCiSoftLinenBg = Color(0xFFF2EDE3);
const Color kCiSoftLinenAccent = Color(0xFF2F6F6D);
const Color kCiSoftLinenText = Color(0xFF2C2A26);

const String kLastBreakDatePrefsKey = 'last_break_date';
const String kLastTopHalfResetByBreakDateKey = 'last_tophalf_reset_by_break';

const String kAppModePrefsKey = 'mode';
const String kAppModeSingleValue = 'single';
const String kBubbleTopPrefsKey = 'quick_overlay_bubble_top_v2';

const double kBubbleHandleHeight = 72.0;
const double kBubbleHandleMinVisualWidth = 14.0;
const double kBubbleHandleMaxVisualWidth = 20.0;
const Duration kBubbleEntryDuration = Duration(milliseconds: 220);
const Duration kBubbleBreathDuration = Duration(milliseconds: 2400);
const Duration kBubbleNudgeDuration = Duration(milliseconds: 240);
const Duration kBubbleModeTransitionDuration = Duration(milliseconds: 220);
const double kBubbleBreathMinScale = 0.985;
const double kBubbleBreathMaxScale = 1.015;
const double kBubbleAlertVisualWidth = 36.0;
const Duration kBubbleAlertCycleDuration = Duration(milliseconds: 1400);
const Duration kBubbleAlertResizeDuration = Duration(milliseconds: 280);
const Duration kBubbleAlertPunchDuration = Duration(milliseconds: 320);
const Color kBubbleAlertRed = Color(0xFFFF1744);
const Color kBubbleAlertGreen = Color(0xFF00C853);

ThemeData _buildOverlayTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: kCiSoftLinenAccent,
    brightness: Brightness.light,
  ).copyWith(
    surface: const Color(0xFFF7F4EE),
    onSurface: kCiSoftLinenText,
    onSurfaceVariant: const Color(0xFF6B6862),
    primaryContainer: const Color(0xFFBFD9D6),
    secondaryContainer: const Color(0xFFDDEAE7),
    outlineVariant: const Color(0xFFC9C2B7),
    shadow: Colors.black,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: InkRipple.splashFactory,
  );
}

enum OverlayUIMode {
  bubble,
  topHalf,
  checkoutNudge,
  workFinished,
}

class QuickOverlayApp extends StatelessWidget {
  const QuickOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildOverlayTheme(),
      home: const QuickOverlayHome(),
    );
  }
}

class QuickOverlayHome extends StatefulWidget {
  const QuickOverlayHome({super.key});

  @override
  State<QuickOverlayHome> createState() => _QuickOverlayHomeState();
}

class _QuickOverlayHomeState extends State<QuickOverlayHome>
    with TickerProviderStateMixin {
  StreamSubscription<dynamic>? _sub;

  late DateTime _overlayStartedAt;
  Duration _elapsed = Duration.zero;
  Timer? _tickTimer;
  DateTime? _scheduledCheckoutEnd;
  bool _checkoutBoundaryInFlight = false;
  bool _checkoutOverdue = false;

  late final AnimationController _entryController;
  late final Animation<double> _entryProgress;

  late final AnimationController _breathController;
  late final Animation<double> _breathScale;

  late final AnimationController _nudgeController;
  late Animation<Offset> _nudgeOffset;

  late final AnimationController _checkoutAlertController;
  late final AnimationController _checkoutPunchController;
  late final Animation<double> _checkoutPunchScale;
  Timer? _attentionTimer;
  int _attentionStep = 0;
  bool _reduceMotion = false;
  bool _motionConfigured = false;
  bool _isDraggingBubble = false;

  OverlayUIMode _uiMode = OverlayUIMode.bubble;
  bool _isSingleMode = false;

  bool get _topHalfAllowed => !_isSingleMode;

  bool get _bubbleModeActive =>
      _isSingleMode || _uiMode == OverlayUIMode.bubble;

  String get _motionModeName =>
      _isSingleMode ? 'single_bubble' : _uiMode.name;

  Timer? _shortBreakTimer;
  int _shortBreakSeq = 0;
  bool _shortBreakActive = false;

  OverlayEdgeSide _side = OverlayEdgeSide.left;
  double _bubbleTop = 200.0;
  bool _bubbleTopLoaded = false;

  @override
  void initState() {
    super.initState();

    _loadAppMode();
    _loadEdgeSide();
    _loadBubbleTop();

    _overlayStartedAt = DateTime.now();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _elapsed = now.difference(_overlayStartedAt);
      });
      _handleCheckoutBoundaryTick(now);
    });

    _entryController = AnimationController(
      vsync: this,
      duration: kBubbleEntryDuration,
    );
    _entryProgress = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );

    _breathController = AnimationController(
      vsync: this,
      duration: kBubbleBreathDuration,
    );

    _breathScale = Tween<double>(
      begin: kBubbleBreathMinScale,
      end: kBubbleBreathMaxScale,
    ).animate(
      CurvedAnimation(
        parent: _breathController,
        curve: Curves.easeInOut,
      ),
    );

    _nudgeController = AnimationController(
      vsync: this,
      duration: kBubbleNudgeDuration,
    );

    _checkoutAlertController = AnimationController(
      vsync: this,
      duration: kBubbleAlertCycleDuration,
    );

    _checkoutPunchController = AnimationController(
      vsync: this,
      duration: kBubbleAlertPunchDuration,
    );
    _checkoutPunchScale = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.12).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 55,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.12, end: 1.0).chain(
          CurveTween(curve: Curves.easeInOutCubic),
        ),
        weight: 45,
      ),
    ]).animate(_checkoutPunchController);

    _rebuildNudgeOffset();

    _sub = FlutterOverlayWindow.overlayListener.listen((event) {
      unawaited(_handleOverlayEvent(event));
    });

    debugPrint(
      '[QuickOverlayBubble] initialized interactionWidth=$kEdgeStripWidth visualWidth=$kBubbleHandleMaxVisualWidth height=$kBubbleHandleHeight',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_motionConfigured && reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    _motionConfigured = true;
    _configureMotion();
  }

  void _configureMotion() {
    _attentionTimer?.cancel();
    _nudgeController.stop();

    if (_reduceMotion) {
      _entryController.value = 1.0;
      _nudgeController.value = 0.0;
    } else {
      if (_entryController.value < 1.0) {
        _entryController.forward();
      }
      if (_bubbleModeActive && !_checkoutOverdue) {
        _scheduleAttentionNudges();
      }
    }

    _syncBreathForMode(source: 'motion_config');
    _syncCheckoutAlertMotion(source: 'motion_config');

    debugPrint(
      '[QuickOverlayBubble] motion_config reduced=$_reduceMotion mode=$_motionModeName bubbleActive=$_bubbleModeActive entryMs=${kBubbleEntryDuration.inMilliseconds} breathMs=${kBubbleBreathDuration.inMilliseconds} nudgeMs=${kBubbleNudgeDuration.inMilliseconds}',
    );
  }

  void _syncBreathForMode({required String source}) {
    if (!_motionConfigured) return;

    final shouldAnimate =
        !_reduceMotion && _bubbleModeActive && !_checkoutOverdue;
    if (shouldAnimate) {
      if (!_breathController.isAnimating) {
        _breathController.repeat(reverse: true);
        debugPrint(
          '[QuickOverlayBubble] breath_resume source=$source mode=$_motionModeName',
        );
      }
      return;
    }

    final wasAnimating = _breathController.isAnimating;
    final wasCentered = (_breathController.value - 0.5).abs() < 0.0001;
    _breathController.stop();
    _breathController.value = 0.5;

    if (wasAnimating || !wasCentered) {
      debugPrint(
        '[QuickOverlayBubble] breath_pause source=$source mode=$_motionModeName reduced=$_reduceMotion',
      );
    }
  }

  void _syncCheckoutAlertMotion({required String source}) {
    if (!_motionConfigured) return;

    final shouldAnimate =
        !_reduceMotion && _bubbleModeActive && _checkoutOverdue;
    if (shouldAnimate) {
      if (!_checkoutAlertController.isAnimating) {
        _checkoutAlertController.repeat();
        debugPrint(
          '[QuickOverlayBubble] checkout_alert_resume source=$source cycleMs=${kBubbleAlertCycleDuration.inMilliseconds}',
        );
      }
      return;
    }

    final wasAnimating = _checkoutAlertController.isAnimating;
    _checkoutAlertController.stop();
    _checkoutAlertController.value = 0.0;
    if (!_checkoutOverdue) {
      _checkoutPunchController.stop();
      _checkoutPunchController.value = 0.0;
    } else if (_reduceMotion) {
      _checkoutPunchController.value = 1.0;
    }

    if (wasAnimating) {
      debugPrint(
        '[QuickOverlayBubble] checkout_alert_pause source=$source reduced=$_reduceMotion overdue=$_checkoutOverdue',
      );
    }
  }

  void _setStateAndSyncBreath(
    VoidCallback update, {
    required String source,
  }) {
    if (!mounted) return;
    setState(update);
    _syncBreathForMode(source: source);
    _syncCheckoutAlertMotion(source: source);
  }

  void _setCheckoutOverdue(
    bool overdue, {
    required String source,
  }) {
    if (!mounted) return;
    final changed = _checkoutOverdue != overdue;
    if (changed) {
      setState(() {
        _checkoutOverdue = overdue;
      });
    }

    if (overdue) {
      _attentionTimer?.cancel();
      _nudgeController.stop();
      _nudgeController.value = 0.0;
      if (_reduceMotion) {
        _checkoutPunchController.value = 1.0;
      } else if (changed) {
        _checkoutPunchController.forward(from: 0.0);
      }
    } else {
      _checkoutPunchController.stop();
      _checkoutPunchController.value = 0.0;
      if (changed && !_reduceMotion && _bubbleModeActive) {
        _scheduleAttentionNudges();
      }
    }

    _syncBreathForMode(source: source);
    _syncCheckoutAlertMotion(source: source);

    if (changed) {
      debugPrint(
        '[QuickOverlayBoundary] bubble_alert source=$source overdue=$overdue nativeResize=false visualWidth=${overdue ? kBubbleAlertVisualWidth : kBubbleHandleMaxVisualWidth}',
      );
    }
  }

  bool _nativeWindowIsBubble() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final currentWidth = view.physicalSize.width.round();
    final bubblePhysicalWidth =
        (kEdgeStripWidth * view.devicePixelRatio).round();
    return currentWidth <= bubblePhysicalWidth + 8;
  }

  void _handleCheckoutBoundaryTick(DateTime now) {
    if (_isSingleMode || _checkoutBoundaryInFlight) return;
    final scheduledEnd = _scheduledCheckoutEnd;
    if (scheduledEnd == null || now.isBefore(scheduledEnd)) return;
    _scheduledCheckoutEnd = null;
    unawaited(
      _refreshLocalCheckoutBoundary(
        source: 'scheduled_end_boundary',
      ),
    );
  }

  Future<void> _refreshLocalCheckoutBoundary({
    required String source,
  }) async {
    if (_checkoutBoundaryInFlight) return;
    _checkoutBoundaryInFlight = true;

    try {
      if (_isSingleMode) {
        _scheduledCheckoutEnd = null;
        _setCheckoutOverdue(false, source: '${source}_single_mode');
        return;
      }

      final decision = await CheckoutNudgeGuard.evaluate();
      if (!mounted) return;

      switch (decision.type) {
        case CheckoutOverlayDecisionType.none:
          final scheduledEnd = decision.scheduledEnd;
          _scheduledCheckoutEnd = scheduledEnd != null &&
                  scheduledEnd.isAfter(DateTime.now())
              ? scheduledEnd
              : null;
          _setCheckoutOverdue(false, source: '${source}_none');
          debugPrint(
            '[QuickOverlayBoundary] refresh source=$source type=none scheduled=${_scheduledCheckoutEnd != null}',
          );
          break;
        case CheckoutOverlayDecisionType.checkoutNudge:
          _scheduledCheckoutEnd = null;
          _cancelShortBreak();
          _attentionTimer?.cancel();
          if (_nativeWindowIsBubble()) {
            if (_uiMode != OverlayUIMode.bubble) {
              _setStateAndSyncBreath(
                () {
                  _uiMode = OverlayUIMode.bubble;
                },
                source: 'local_checkout_bubble_geometry',
              );
            }
            _setCheckoutOverdue(true, source: source);
            debugPrint(
              '[QuickOverlayBoundary] transition source=$source mode=bubble_attention state=checkoutOverdue localOnly=true nativeResize=false',
            );
          } else {
            _setCheckoutOverdue(false, source: '${source}_panel_geometry');
            _setStateAndSyncBreath(
              () {
                _uiMode = OverlayUIMode.checkoutNudge;
                _overlayStartedAt = DateTime.now();
                _elapsed = Duration.zero;
              },
              source: 'local_checkout_boundary',
            );
            debugPrint(
              '[QuickOverlayBoundary] transition source=$source mode=checkoutNudge localOnly=true nativeResize=false',
            );
          }
          break;
        case CheckoutOverlayDecisionType.workFinished:
          _scheduledCheckoutEnd = null;
          _cancelShortBreak();
          _attentionTimer?.cancel();
          _setCheckoutOverdue(false, source: source);
          if (_nativeWindowIsBubble()) {
            if (_uiMode != OverlayUIMode.bubble) {
              _setStateAndSyncBreath(
                () {
                  _uiMode = OverlayUIMode.bubble;
                },
                source: 'local_work_finished_bubble_geometry',
              );
            }
            debugPrint(
              '[QuickOverlayBoundary] transition source=$source mode=bubble state=workFinished localOnly=true nativeResize=false',
            );
          } else {
            _setStateAndSyncBreath(
              () {
                _uiMode = OverlayUIMode.workFinished;
                _overlayStartedAt = DateTime.now();
                _elapsed = Duration.zero;
              },
              source: 'local_work_finished',
            );
            debugPrint(
              '[QuickOverlayBoundary] transition source=$source mode=workFinished localOnly=true nativeResize=false',
            );
          }
          break;
      }
    } catch (error) {
      debugPrint(
        '[QuickOverlayBoundary] refresh_failure source=$source type=${error.runtimeType}',
      );
      _scheduleBoundaryRetry();
    } finally {
      _checkoutBoundaryInFlight = false;
    }
  }

  void _scheduleBoundaryRetry() {
    if (_isSingleMode) return;
    _scheduledCheckoutEnd = DateTime.now().add(
      const Duration(seconds: 15),
    );
  }

  void _scheduleAttentionNudges() {
    _attentionTimer?.cancel();
    if (_reduceMotion || !_bubbleModeActive || _checkoutOverdue) return;
    _attentionStep = 0;
    _attentionTimer = Timer(const Duration(milliseconds: 650), () {
      unawaited(_runAttentionNudge());
    });
  }

  Future<void> _runAttentionNudge() async {
    if (!mounted ||
        _reduceMotion ||
        !_bubbleModeActive ||
        _checkoutOverdue ||
        _nudgeController.isAnimating) {
      return;
    }
    try {
      await _nudgeController.forward(from: 0.0);
      if (!mounted || _reduceMotion) return;
      await _nudgeController.reverse();
    } catch (_) {
      return;
    }

    if (!mounted || _reduceMotion) return;
    _attentionStep += 1;
    if (_attentionStep >= 2) return;
    _attentionTimer = Timer(const Duration(milliseconds: 900), () {
      unawaited(_runAttentionNudge());
    });
  }

  Future<void> _handleOverlayEvent(dynamic event) async {
    if (!mounted) return;
    if (await OverlayAccessGuard.closeIfBlocked()) return;
    if (!mounted) return;

    final singleMode = await _syncAppMode();
    if (!mounted) return;

    if (event == '__work_finished__') {
      _scheduledCheckoutEnd = null;
      _cancelShortBreak();
      if (!mounted) return;
      _setCheckoutOverdue(false, source: 'work_finished');
      _setStateAndSyncBreath(
        () {
          _uiMode = singleMode || _nativeWindowIsBubble()
              ? OverlayUIMode.bubble
              : OverlayUIMode.workFinished;
          _overlayStartedAt = DateTime.now();
          _elapsed = Duration.zero;
        },
        source: 'work_finished',
      );
      return;
    }

    if (event == '__checkout_nudge__') {
      _scheduledCheckoutEnd = null;
      _cancelShortBreak();
      if (!mounted) return;
      if (!singleMode && _nativeWindowIsBubble()) {
        _setStateAndSyncBreath(
          () {
            _uiMode = OverlayUIMode.bubble;
          },
          source: 'checkout_nudge_bubble_geometry',
        );
        _setCheckoutOverdue(true, source: 'checkout_nudge');
      } else {
        _setCheckoutOverdue(false, source: 'checkout_nudge_panel_geometry');
        _setStateAndSyncBreath(
          () {
            _uiMode = singleMode
                ? OverlayUIMode.bubble
                : OverlayUIMode.checkoutNudge;
            _overlayStartedAt = DateTime.now();
            _elapsed = Duration.zero;
          },
          source: 'checkout_nudge',
        );
      }
      return;
    }

    if (event is String && event.startsWith('__mode:')) {
      _cancelShortBreak();

      final raw = event.substring('__mode:'.length);
      _setStateAndSyncBreath(
        () {
          if (raw.startsWith('topHalf')) {
            _uiMode =
                _topHalfAllowed ? OverlayUIMode.topHalf : OverlayUIMode.bubble;
          } else {
            _uiMode = OverlayUIMode.bubble;
          }
        },
        source: 'mode_event',
      );
      return;
    }

    if (event == '__collapse__') {
      _cancelShortBreak();
      _loadEdgeSide();
      if (!mounted) return;
      setState(() {
        _overlayStartedAt = DateTime.now();
        _elapsed = Duration.zero;
      });
      unawaited(
        _refreshLocalCheckoutBoundary(
          source: 'collapse_event',
        ),
      );
    }
  }

  Future<bool> _syncAppMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final mode = prefs.getString(kAppModePrefsKey);

    if (OverlayAccessGuard.isBlockedMode(mode)) {
      await OverlayAccessGuard.closeIfBlocked();
      return _isSingleMode;
    }

    final isSingle = OverlayAccessGuard.normalizeMode(mode) == kAppModeSingleValue;

    if (!mounted) return isSingle;
    _setStateAndSyncBreath(
      () {
        _isSingleMode = isSingle;
        if (_isSingleMode) {
          _checkoutOverdue = false;
        }
        if (_isSingleMode && _uiMode != OverlayUIMode.bubble) {
          _cancelShortBreak();
          _uiMode = OverlayUIMode.bubble;
        }
      },
      source: 'app_mode_sync',
    );
    return isSingle;
  }

  Future<void> _loadAppMode() async {
    final isSingle = await _syncAppMode();
    if (!mounted) return;
    if (isSingle) {
      _scheduledCheckoutEnd = null;
      return;
    }
    await _refreshLocalCheckoutBoundary(
      source: 'overlay_init',
    );
  }

  Future<void> _loadEdgeSide() async {
    final side = await OverlayEdgeSideConfig.getSide();
    if (!mounted) return;
    setState(() {
      _side = side;
      _rebuildNudgeOffset();
    });
    if (_motionConfigured && !_reduceMotion && _bubbleModeActive) {
      _scheduleAttentionNudges();
    }
  }

  Future<void> _loadBubbleTop() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(kBubbleTopPrefsKey) ?? 200.0;
    if (!mounted) return;
    setState(() {
      _bubbleTop = saved;
      _bubbleTopLoaded = true;
    });
  }

  Future<void> _saveBubbleTop(double top) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kBubbleTopPrefsKey, top);
  }

  double _clampBubbleTop(double raw, double height) {
    final maxTop = (height - kBubbleHandleHeight).clamp(0.0, double.infinity);
    return raw.clamp(0.0, maxTop).toDouble();
  }

  void _rebuildNudgeOffset() {
    final end = _side == OverlayEdgeSide.left
        ? const Offset(0.16, 0)
        : const Offset(-0.16, 0);
    _nudgeOffset = Tween<Offset>(
      begin: Offset.zero,
      end: end,
    )
        .chain(
          CurveTween(curve: Curves.easeInOut),
        )
        .animate(_nudgeController);
  }

  void _cancelShortBreak() {
    _shortBreakTimer?.cancel();
    _shortBreakTimer = null;
    _shortBreakActive = false;
  }

  void _startShortBreak() {
    if (!_topHalfAllowed) return;
    if (_uiMode != OverlayUIMode.topHalf) return;

    _shortBreakSeq += 1;
    final seq = _shortBreakSeq;

    _shortBreakTimer?.cancel();
    _shortBreakActive = true;

    _setStateAndSyncBreath(
      () {
        _overlayStartedAt = DateTime.now();
        _elapsed = Duration.zero;
        _uiMode = OverlayUIMode.bubble;
      },
      source: 'short_break_start',
    );

    _shortBreakTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (!_shortBreakActive) return;
      if (seq != _shortBreakSeq) return;

      _setStateAndSyncBreath(
        () {
          _uiMode =
              _topHalfAllowed ? OverlayUIMode.topHalf : OverlayUIMode.bubble;
          _shortBreakActive = false;
          _overlayStartedAt = DateTime.now();
          _elapsed = Duration.zero;
        },
        source: 'short_break_end',
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tickTimer?.cancel();
    _attentionTimer?.cancel();
    _shortBreakTimer?.cancel();
    _entryController.dispose();
    _breathController.dispose();
    _nudgeController.dispose();
    _checkoutAlertController.dispose();
    _checkoutPunchController.dispose();
    super.dispose();
  }

  Future<void> _sendBackToMain(String msg) async {
    await FlutterOverlayWindow.shareData(msg);
  }

  Future<void> _launchMainApp() async {
    debugPrint('[QuickOverlayBubble] launch_main_start');
    try {
      await FlutterOverlayWindow.closeOverlay();
      FlutterForegroundTask.launchApp('/');
      await _sendBackToMain('open_main_app');
    } catch (_) {
      debugPrint('[QuickOverlayBubble] launch_main_failure');
      if (!mounted) return;
      _setStateAndSyncBreath(
        () {
          _overlayStartedAt = DateTime.now();
          _elapsed = Duration.zero;
          _uiMode = OverlayUIMode.bubble;
        },
        source: 'launch_main_failure',
      );
    }
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _resetPanel() async {
    _cancelShortBreak();

    final prefs = await SharedPreferences.getInstance();

    final lastBreakDate = prefs.getString(kLastBreakDatePrefsKey);
    final lastTopHalfResetByBreakDate =
        prefs.getString(kLastTopHalfResetByBreakDateKey);

    final todayStr = _formatDate(DateTime.now());
    final hasRestPressedToday = lastBreakDate == todayStr;

    if (!hasRestPressedToday) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text(
              '휴게 기록이 없습니다',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            content: const Text(
              '오늘은 아직 "휴게 사용 확인"이 기록되지 않았습니다.\n메인 앱에서 먼저 휴게 사용을 기록해 주세요.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF4B5563),
              ),
            ),
            actions: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF111827),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('확인'),
                ),
              ),
            ],
          );
        },
      );
      return;
    }

    final alreadyResetOnceForToday =
        lastTopHalfResetByBreakDate == lastBreakDate;

    if (alreadyResetOnceForToday) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text(
              '오늘 상단 패널 해제 완료',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            content: const Text(
              '오늘 휴게 이후 상단 50% 포그라운드 모드는\n이미 한 번 해제되었습니다.\n\n추가로 상단 모드를 변경하려면\n메인 앱에서 직접 설정해 주세요.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF4B5563),
              ),
            ),
            actions: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF111827),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('확인'),
                ),
              ),
            ],
          );
        },
      );
      return;
    }

    if (_uiMode == OverlayUIMode.topHalf) {
      _setStateAndSyncBreath(
        () {
          _overlayStartedAt = DateTime.now();
          _elapsed = Duration.zero;
          _uiMode = OverlayUIMode.bubble;
        },
        source: 'reset_panel',
      );

      if (lastBreakDate != null && lastBreakDate.isNotEmpty) {
        await prefs.setString(
          kLastTopHalfResetByBreakDateKey,
          lastBreakDate,
        );
      }
    }
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildEdgeStrip(BuildContext context) {
    final dockRight = _side == OverlayEdgeSide.right;
    final hostWidth = kEdgeStripWidth;
    final normalVisualWidth = hostWidth
        .clamp(kBubbleHandleMinVisualWidth, kBubbleHandleMaxVisualWidth)
        .toDouble();
    final targetVisualWidth = _checkoutOverdue
        ? kBubbleAlertVisualWidth.clamp(0.0, hostWidth).toDouble()
        : normalVisualWidth;
    final dragDuration =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 140);
    final resizeDuration =
        _reduceMotion ? Duration.zero : kBubbleAlertResizeDuration;

    return SizedBox(
      width: hostWidth,
      height: kBubbleHandleHeight,
      child: AnimatedBuilder(
        animation: _entryProgress,
        builder: (context, _) {
          final progress = _reduceMotion ? 1.0 : _entryProgress.value;
          final horizontalOffset =
              (dockRight ? 1.0 : -1.0) * (1.0 - progress) * 8.0;
          final entryScale = 0.96 + (0.04 * progress);
          return Opacity(
            opacity: progress.clamp(0.0, 1.0).toDouble(),
            child: Transform.translate(
              offset: Offset(horizontalOffset, 0),
              child: Transform.scale(
                scale: entryScale,
                alignment:
                    dockRight ? Alignment.centerRight : Alignment.centerLeft,
                child: AnimatedBuilder(
                  animation: _checkoutAlertController,
                  builder: (context, _) {
                    return Align(
                      alignment: dockRight
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: SlideTransition(
                        position: _nudgeOffset,
                        child: ScaleTransition(
                          scale: _breathScale,
                          child: ScaleTransition(
                            scale: _checkoutPunchScale,
                            alignment: dockRight
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: AnimatedScale(
                              scale: _isDraggingBubble ? 1.025 : 1.0,
                              duration: dragDuration,
                              curve: Curves.easeOutCubic,
                              child: AnimatedContainer(
                                width: targetVisualWidth,
                                height: kBubbleHandleHeight,
                                duration: resizeDuration,
                                curve: Curves.easeOutCubic,
                                child: _OverlayEdgeHandle(
                                  width: targetVisualWidth,
                                  height: kBubbleHandleHeight,
                                  dockRight: dockRight,
                                  elapsedText: _formatElapsed(_elapsed),
                                  checkoutOverdue: _checkoutOverdue,
                                  alertProgress: _reduceMotion
                                      ? 0.0
                                      : _checkoutAlertController.value,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBubbleOverlay(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final top = _bubbleTopLoaded
            ? _clampBubbleTop(_bubbleTop, constraints.maxHeight)
            : _clampBubbleTop(200.0, constraints.maxHeight);

        return SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Stack(
            children: [
              Positioned(
                top: top,
                left: _side == OverlayEdgeSide.left ? 0 : null,
                right: _side == OverlayEdgeSide.right ? 0 : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _launchMainApp,
                  onPanStart: (_) {
                    if (_isDraggingBubble) return;
                    setState(() {
                      _isDraggingBubble = true;
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _bubbleTop = _clampBubbleTop(
                        _bubbleTop + details.delta.dy,
                        constraints.maxHeight,
                      );
                    });
                  },
                  onPanEnd: (_) async {
                    final topToSave = _clampBubbleTop(
                      _bubbleTop,
                      constraints.maxHeight,
                    );
                    setState(() {
                      _isDraggingBubble = false;
                      _bubbleTop = topToSave;
                    });
                    await _saveBubbleTop(topToSave);
                    debugPrint(
                      '[QuickOverlayBubble] drag_end top=${topToSave.toStringAsFixed(1)}',
                    );
                  },
                  onPanCancel: () {
                    if (!_isDraggingBubble) return;
                    setState(() {
                      _isDraggingBubble = false;
                    });
                  },
                  child: _buildEdgeStrip(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopHalfOverlay(
    BuildContext context, {
    bool checkoutNudge = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          color: Colors.white,
          child: FittedBox(
            alignment: Alignment.topCenter,
            fit: BoxFit.scaleDown,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                checkoutNudge
                                    ? '퇴근 시간이 지났습니다.'
                                    : '앱이 아직 실행 중입니다.',
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text.rich(
                                TextSpan(
                                  style: const TextStyle(
                                    color: Color(0xFF4B5563),
                                    fontSize: 11,
                                  ),
                                  children: checkoutNudge
                                      ? const [
                                          TextSpan(text: '아직 오늘 '),
                                          TextSpan(
                                            text: '퇴근 기록',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFFDC2626),
                                            ),
                                          ),
                                          TextSpan(
                                            text: '이 없습니다.\n앱으로 돌아가 퇴근 버튼을 눌러주세요.',
                                          ),
                                        ]
                                      : const [
                                          TextSpan(text: '당일 근무가 끝난 분들은 꼭 '),
                                          TextSpan(
                                            text: '퇴근',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFFDC2626),
                                            ),
                                          ),
                                          TextSpan(
                                            text: ' 버튼을\n눌러주시기 바랍니다.',
                                          ),
                                        ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: kCiSoftLinenAccent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                size: 14,
                                color: kCiSoftLinenBg,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatElapsed(_elapsed),
                                style: const TextStyle(
                                  color: kCiSoftLinenBg,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: const Color(0xFFF9FAFB),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(
                                Icons.fact_check_outlined,
                                size: 18,
                                color: Color(0xFF4B5563),
                              ),
                              SizedBox(width: 6),
                              Text(
                                '오늘 하루 체크리스트',
                                style: TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '공통 체크',
                            style: TextStyle(
                              color: Color(0xFF4B5563),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildChecklistItem(
                            icon: Icons.check_circle_outline,
                            label: '오늘 하루 휴게시간 버튼은 눌렀는지',
                          ),
                          const SizedBox(height: 4),
                          _buildChecklistItem(
                            icon: Icons.check_circle_outline,
                            label: '퇴근하기 전, 유니폼 및 근무지 정리는 했는지',
                          ),
                          const SizedBox(height: 4),
                          _buildChecklistItem(
                            icon: Icons.check_circle_outline,
                            label: '입차 완료 테이블은 "비우기"를 했는지',
                          ),
                          const SizedBox(height: 8),
                          const Divider(
                            color: Color(0xFFE5E7EB),
                            height: 16,
                            thickness: 1,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '보고자 혹은 오픈조 체크',
                            style: TextStyle(
                              color: Color(0xFF4B5563),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildChecklistItem(
                            icon: Icons.check_circle_outline,
                            label: '오픈조는 퇴근조에게 업무 인수 인계를 했는지',
                          ),
                          const SizedBox(height: 4),
                          _buildChecklistItem(
                            icon: Icons.check_circle_outline,
                            label: '오픈조는 오늘 하루 업무 시작에 대해 보고 했는지',
                          ),
                          const SizedBox(height: 8),
                          const Divider(
                            color: Color(0xFFE5E7EB),
                            height: 16,
                            thickness: 1,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '보고자 혹은 퇴근조 체크',
                            style: TextStyle(
                              color: Color(0xFF4B5563),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildChecklistItem(
                            icon: Icons.check_circle_outline,
                            label: '퇴근조는 오늘 하루 업무 결과에 대해 보고 했는지',
                          ),
                          const SizedBox(height: 4),
                          _buildChecklistItem(
                            icon: Icons.check_circle_outline,
                            label: '퇴근조는 오늘 하루 업무 종료에 대한 마감을 했는지',
                          ),
                          const SizedBox(height: 10),
                          Text(
                            checkoutNudge
                                ? '퇴근 처리가 아직 완료되지 않았습니다.\n아래의 "앱으로 돌아가 퇴근하기" 버튼을 눌러\n오늘 근무를 종료해 주세요.'
                                : '위 항목 중 하나라도 놓쳤다면,\n아래의 "앱으로 돌아가기" 버튼을 눌러\n지금 바로 처리해 주세요.',
                            style: const TextStyle(
                              color: Color(0xFFF97316),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (checkoutNudge)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _launchMainApp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          icon: const Icon(
                            Icons.logout_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            '앱으로 돌아가 퇴근하기',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: ElevatedButton.icon(
                              onPressed: _launchMainApp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF111827),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                '앱으로 돌아가기',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: OutlinedButton.icon(
                              onPressed: _startShortBreak,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF111827),
                                side: const BorderSide(
                                  color: Color(0xFF9CA3AF),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              icon: const Icon(Icons.timer_rounded, size: 18),
                              label: const Text(
                                '15초 쉬기',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 4,
                            child: OutlinedButton.icon(
                              onPressed: _resetPanel,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF111827),
                                side: const BorderSide(
                                  color: Color(0xFF9CA3AF),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text(
                                '휴게 중입니다',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
  }

  Widget _buildWorkFinishedOverlay(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          color: Colors.white,
          child: FittedBox(
            alignment: Alignment.topCenter,
            fit: BoxFit.scaleDown,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.task_alt_rounded,
                            color: Color(0xFF2563EB),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                '오늘의 업무는 종료되었습니다.',
                                style: TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '이미 오늘 퇴근 처리가 완료되었습니다. 앱을 종료하려면 아래 경로를 확인해 주세요.',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: const Color(0xFFF9FAFB),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(
                                Icons.power_settings_new_rounded,
                                size: 18,
                                color: Color(0xFF2563EB),
                              ),
                              SizedBox(width: 6),
                              Text(
                                '앱 종료 경로',
                                style: TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildChecklistItem(
                            icon: Icons.more_horiz_rounded,
                            label: '더보기로 이동합니다.',
                          ),
                          const SizedBox(height: 6),
                          _buildChecklistItem(
                            icon: Icons.tune_rounded,
                            label: '모드 선택을 누릅니다.',
                          ),
                          const SizedBox(height: 6),
                          _buildChecklistItem(
                            icon: Icons.account_circle_outlined,
                            label: '환영합니다 화면의 윗 아이콘을 누릅니다.',
                          ),
                          const SizedBox(height: 6),
                          _buildChecklistItem(
                            icon: Icons.logout_rounded,
                            label: '앱 종료 버튼을 눌러 종료합니다.',
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '퇴근 처리는 이미 완료되어 있습니다. 앱이 계속 실행 중이면 위 순서대로 앱 종료를 진행해 주세요.',
                            style: TextStyle(
                              color: Color(0xFF2563EB),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _launchMainApp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        icon: const Icon(
                          Icons.open_in_new_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          '앱으로 돌아가기',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChecklistItem({
    required IconData icon,
    required String label,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF4B5563)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    String modeKey;

    if (_isSingleMode) {
      modeKey = 'single_bubble';
      body = _buildBubbleOverlay(context);
    } else if (_uiMode == OverlayUIMode.workFinished) {
      modeKey = 'work_finished';
      body = _buildWorkFinishedOverlay(context);
    } else if (_uiMode == OverlayUIMode.checkoutNudge) {
      modeKey = 'checkout_nudge';
      body = _buildTopHalfOverlay(
        context,
        checkoutNudge: true,
      );
    } else {
      final effectiveMode =
          _uiMode == OverlayUIMode.topHalf && _topHalfAllowed
              ? OverlayUIMode.topHalf
              : OverlayUIMode.bubble;
      if (effectiveMode == OverlayUIMode.topHalf) {
        modeKey = 'top_half';
        body = _buildTopHalfOverlay(context);
      } else {
        modeKey = 'bubble';
        body = _buildBubbleOverlay(context);
      }
    }

    final transitionDuration =
        _reduceMotion ? Duration.zero : kBubbleModeTransitionDuration;

    return Material(
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: transitionDuration,
        reverseDuration: transitionDuration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          if (_reduceMotion) return child;
          final offset = Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: offset,
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey<String>(modeKey),
          child: body,
        ),
      ),
    );
  }
}

class _OverlayEdgeHandle extends StatelessWidget {
  final double width;
  final double height;
  final bool dockRight;
  final String elapsedText;
  final bool checkoutOverdue;
  final double alertProgress;

  const _OverlayEdgeHandle({
    required this.width,
    required this.height,
    required this.dockRight,
    required this.elapsedText,
    required this.checkoutOverdue,
    required this.alertProgress,
  });

  Color _alertColor(double progress) {
    final p = progress % 1.0;
    if (p < 0.42) return kBubbleAlertRed;
    if (p < 0.50) {
      return Color.lerp(
        kBubbleAlertRed,
        kBubbleAlertGreen,
        (p - 0.42) / 0.08,
      )!;
    }
    if (p < 0.92) return kBubbleAlertGreen;
    return Color.lerp(
      kBubbleAlertGreen,
      kBubbleAlertRed,
      (p - 0.92) / 0.08,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final normalIcon =
        dockRight ? Icons.chevron_left_rounded : Icons.chevron_right_rounded;
    final icon = checkoutOverdue ? Icons.priority_high_rounded : normalIcon;
    final turns = dockRight ? 3 : 1;
    final alertColor = _alertColor(alertProgress);
    final bg0 = checkoutOverdue
        ? alertColor
        : Color.alphaBlend(
            cs.primaryContainer.withOpacity(0.58),
            cs.surface,
          );
    final bg1 = checkoutOverdue
        ? alertColor
        : Color.alphaBlend(
            cs.secondaryContainer.withOpacity(0.40),
            cs.surface,
          );
    final border = checkoutOverdue
        ? Colors.white.withOpacity(0.98)
        : cs.outlineVariant.withOpacity(0.88);
    final foreground = checkoutOverdue
        ? Colors.white
        : cs.onSurface.withOpacity(0.92);
    final secondaryForeground = checkoutOverdue
        ? Colors.white.withOpacity(0.96)
        : cs.onSurfaceVariant.withOpacity(0.84);
    final gripColor = checkoutOverdue
        ? Colors.white.withOpacity(0.92)
        : cs.onSurfaceVariant.withOpacity(0.56);
    final shadowColor = checkoutOverdue
        ? alertColor.withOpacity(0.86)
        : cs.shadow.withOpacity(0.22);

    return Semantics(
      button: true,
      label: checkoutOverdue
          ? '퇴근 시간이 지났습니다. 앱으로 돌아가 퇴근해 주세요. 경과 시간 $elapsedText'
          : '앱으로 돌아가기, 경과 시간 $elapsedText',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              blurRadius: checkoutOverdue ? 22 : 16,
              spreadRadius: checkoutOverdue ? 3.5 : 0,
              offset: checkoutOverdue ? Offset.zero : const Offset(0, 6),
              color: shadowColor,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: checkoutOverdue ? 8 : 18,
              sigmaY: checkoutOverdue ? 8 : 18,
            ),
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bg0, bg1],
                ),
                border: Border.all(
                  color: border,
                  width: checkoutOverdue ? 2.5 : 1,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = constraints.maxHeight;
                  final compact = availableHeight < 64;
                  final iconSize = checkoutOverdue
                      ? (compact ? 19.0 : 22.0)
                      : (compact ? 15.0 : 18.0);
                  final edgeInset = compact ? 3.0 : 5.0;
                  final timeTop = edgeInset + iconSize + 2;
                  final showGrip = availableHeight >= 62;
                  final timeBottom = showGrip ? 13.0 : edgeInset;

                  return ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          top: edgeInset,
                          left: 0,
                          right: 0,
                          child: Icon(
                            icon,
                            size: iconSize,
                            color: foreground,
                          ),
                        ),
                        Positioned(
                          top: timeTop,
                          bottom: timeBottom,
                          left: 1,
                          right: 1,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: RotatedBox(
                              quarterTurns: turns,
                              child: Text(
                                elapsedText,
                                maxLines: 1,
                                style: TextStyle(
                                  color: secondaryForeground,
                                  fontSize: checkoutOverdue ? 9 : 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: checkoutOverdue ? 0.3 : 0.15,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (showGrip)
                          Positioned(
                            bottom: 5,
                            left: 0,
                            right: 0,
                            child: _GripDots(
                              color: gripColor,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GripDots extends StatelessWidget {
  final Color color;

  const _GripDots({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Dot(color: color),
        const SizedBox(width: 1.5),
        _Dot(color: color),
        const SizedBox(width: 1.5),
        _Dot(color: color),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3.0,
      height: 3.0,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
