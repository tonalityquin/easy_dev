import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/overlay_edge_side_config.dart';
import 'overlay_access_guard.dart';

const Color kCiSoftLinenBg = Color(0xFFF2EDE3);
const Color kCiSoftLinenAccent = Color(0xFF2F6F6D);
const Color kCiSoftLinenText = Color(0xFF2C2A26);

const String kLastBreakDatePrefsKey = 'last_break_date';
const String kLastTopHalfResetByBreakDateKey = 'last_tophalf_reset_by_break';

const String kAppModePrefsKey = 'mode';
const String kAppModeSimpleValue = 'simple';
const String kBubbleTopPrefsKey = 'quick_overlay_bubble_top_v2';

const double kBubbleHandleHeight = 72.0;
const double kBubbleHandleMinVisualWidth = 14.0;
const double kBubbleHandleMaxVisualWidth = 20.0;

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

  late final AnimationController _breathController;
  late final Animation<double> _breathScale;

  late final AnimationController _nudgeController;
  late Animation<Offset> _nudgeOffset;
  Timer? _nudgeTimer;

  OverlayUIMode _uiMode = OverlayUIMode.bubble;
  bool _isSimpleMode = false;

  bool get _topHalfAllowed => !_isSimpleMode;

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
      setState(() {
        _elapsed = DateTime.now().difference(_overlayStartedAt);
      });
    });

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _breathScale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(
        parent: _breathController,
        curve: Curves.easeInOut,
      ),
    );

    _nudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _rebuildNudgeOffset();

    _nudgeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _nudgeController.isAnimating) return;
      _nudgeController.forward(from: 0.0).then((_) {
        if (mounted) {
          _nudgeController.reverse();
        }
      }).catchError((_) {});
    });

    _sub = FlutterOverlayWindow.overlayListener.listen((event) {
      unawaited(_handleOverlayEvent(event));
    });
  }

  Future<void> _handleOverlayEvent(dynamic event) async {
    if (!mounted) return;
    if (await OverlayAccessGuard.closeIfBlocked()) return;
    if (!mounted) return;

    if (event == '__work_finished__') {
      _cancelShortBreak();
      if (!mounted) return;
      setState(() {
        _uiMode = OverlayUIMode.workFinished;
        _overlayStartedAt = DateTime.now();
        _elapsed = Duration.zero;
      });
      return;
    }

    if (event == '__checkout_nudge__') {
      _cancelShortBreak();
      if (!mounted) return;
      setState(() {
        _uiMode = OverlayUIMode.checkoutNudge;
        _overlayStartedAt = DateTime.now();
        _elapsed = Duration.zero;
      });
      return;
    }

    if (event is String && event.startsWith('__mode:')) {
      _cancelShortBreak();

      final raw = event.substring('__mode:'.length);
      setState(() {
        if (raw.startsWith('topHalf')) {
          _uiMode =
              _topHalfAllowed ? OverlayUIMode.topHalf : OverlayUIMode.bubble;
        } else {
          _uiMode = OverlayUIMode.bubble;
        }
      });
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
    }
  }

  Future<void> _loadAppMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(kAppModePrefsKey);

    if (OverlayAccessGuard.isBlockedMode(mode)) {
      await OverlayAccessGuard.closeIfBlocked();
      return;
    }

    final isSimple = OverlayAccessGuard.normalizeMode(mode) == kAppModeSimpleValue;

    if (!mounted) return;
    setState(() {
      _isSimpleMode = isSimple;

      if (_isSimpleMode && _uiMode != OverlayUIMode.checkoutNudge &&
          _uiMode != OverlayUIMode.workFinished) {
        _cancelShortBreak();
        _uiMode = OverlayUIMode.bubble;
      }
    });
  }

  Future<void> _loadEdgeSide() async {
    final side = await OverlayEdgeSideConfig.getSide();
    if (!mounted) return;
    setState(() {
      _side = side;
      _rebuildNudgeOffset();
    });
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
        ? const Offset(0.20, 0)
        : const Offset(-0.20, 0);
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

    setState(() {
      _overlayStartedAt = DateTime.now();
      _elapsed = Duration.zero;
      _uiMode = OverlayUIMode.bubble;
    });

    _shortBreakTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (!_shortBreakActive) return;
      if (seq != _shortBreakSeq) return;

      setState(() {
        _uiMode =
            _topHalfAllowed ? OverlayUIMode.topHalf : OverlayUIMode.bubble;
        _shortBreakActive = false;
        _overlayStartedAt = DateTime.now();
        _elapsed = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tickTimer?.cancel();
    _nudgeTimer?.cancel();
    _shortBreakTimer?.cancel();
    _breathController.dispose();
    _nudgeController.dispose();
    super.dispose();
  }

  Future<void> _sendBackToMain(String msg) async {
    await FlutterOverlayWindow.shareData(msg);
  }

  Future<void> _launchMainApp() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
      FlutterForegroundTask.launchApp('/');
      await _sendBackToMain('open_main_app');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _overlayStartedAt = DateTime.now();
        _elapsed = Duration.zero;
        _uiMode = OverlayUIMode.bubble;
      });
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
      setState(() {
        _overlayStartedAt = DateTime.now();
        _elapsed = Duration.zero;
        _uiMode = OverlayUIMode.bubble;
      });

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
    final visualWidth = hostWidth
        .clamp(kBubbleHandleMinVisualWidth, kBubbleHandleMaxVisualWidth)
        .toDouble();

    return SizedBox(
      width: hostWidth,
      height: kBubbleHandleHeight,
      child: Align(
        alignment: dockRight ? Alignment.centerRight : Alignment.centerLeft,
        child: SlideTransition(
          position: _nudgeOffset,
          child: ScaleTransition(
            scale: _breathScale,
            child: _OverlayEdgeHandle(
              width: visualWidth,
              height: kBubbleHandleHeight,
              dockRight: dockRight,
              elapsedText: _formatElapsed(_elapsed),
            ),
          ),
        ),
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
                    if (_bubbleTop != topToSave) {
                      setState(() {
                        _bubbleTop = topToSave;
                      });
                    }
                    await _saveBubbleTop(topToSave);
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
    if (_uiMode == OverlayUIMode.workFinished) {
      return Material(
        color: Colors.transparent,
        child: _buildWorkFinishedOverlay(context),
      );
    }

    if (_uiMode == OverlayUIMode.checkoutNudge) {
      return Material(
        color: Colors.transparent,
        child: _buildTopHalfOverlay(
          context,
          checkoutNudge: true,
        ),
      );
    }

    final effectiveMode = _uiMode == OverlayUIMode.topHalf && _topHalfAllowed
        ? OverlayUIMode.topHalf
        : OverlayUIMode.bubble;

    if (effectiveMode == OverlayUIMode.topHalf) {
      return Material(
        color: Colors.transparent,
        child: _buildTopHalfOverlay(context),
      );
    }

    return Material(
      color: Colors.transparent,
      child: _buildBubbleOverlay(context),
    );
  }
}

class _OverlayEdgeHandle extends StatelessWidget {
  final double width;
  final double height;
  final bool dockRight;
  final String elapsedText;

  const _OverlayEdgeHandle({
    required this.width,
    required this.height,
    required this.dockRight,
    required this.elapsedText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon =
        dockRight ? Icons.chevron_left_rounded : Icons.chevron_right_rounded;
    final turns = dockRight ? 3 : 1;
    final bg0 = Color.alphaBlend(
      cs.primaryContainer.withOpacity(0.58),
      cs.surface,
    );
    final bg1 = Color.alphaBlend(
      cs.secondaryContainer.withOpacity(0.40),
      cs.surface,
    );
    final border = cs.outlineVariant.withOpacity(0.88);

    return Semantics(
      button: true,
      label: '앱으로 돌아가기, 경과 시간 $elapsedText',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: width,
            height: height,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg0, bg1],
              ),
              border: Border.all(color: border, width: 1),
              boxShadow: [
                BoxShadow(
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                  color: cs.shadow.withOpacity(0.22),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: cs.onSurface.withOpacity(0.92),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 24,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RotatedBox(
                      quarterTurns: turns,
                      child: Text(
                        elapsedText,
                        maxLines: 1,
                        style: TextStyle(
                          color: cs.onSurfaceVariant.withOpacity(0.84),
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.15,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _GripDots(
                  color: cs.onSurfaceVariant.withOpacity(0.56),
                ),
              ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: color),
        const SizedBox(height: 4),
        _Dot(color: color),
        const SizedBox(height: 4),
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
      width: 3.5,
      height: 3.5,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
