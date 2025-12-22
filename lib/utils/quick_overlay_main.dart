import 'dart:async';
import 'dart:ui'; // 글라스(blur) 효과용

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔹 SharedPreferences 추가

/// 오버레이 전체 배경 색상
const Color kOverlayBackgroundColor = Color(0xFF020617);

/// 내부 UI 레이아웃 사이즈들 (윈도우보다 살짝 작게)
const double kBubbleSize = 56.0;
const double kExpandedPanelWidth = 280.0;

/// 상단 포그라운드 모드에서 설계 기준으로 사용할 높이(dp)
/// - main.dart 의 kTopOverlayLogicalHeight 와 같은 값으로 유지(520.0)
const double kTopOverlayDesignHeight = 520.0;

/// 메인 컨트롤러(HomeDashBoardController)에서 사용한 것과 동일한 키
/// 오늘 휴게 버튼 사용 여부를 'YYYY-MM-DD' 형태의 문자열로 저장
const String kLastBreakDatePrefsKey = 'last_break_date';

/// 🔹 "휴게 이후 상단 50% 포그라운드 모드를 자동 해제한 마지막 날짜"
///    - 값 형식은 'YYYY-MM-DD'
///    - last_break_date 와 같으면: "이번 휴게에 대한 해제 기회는 이미 사용함"
const String kLastTopHalfResetByBreakDateKey = 'last_tophalf_reset_by_break';

/// ✅ 앱 모드 SharedPreferences 키/값
/// - 문자열 key: 'mode'
/// - 값이 'simple'이면 topHalf를 금지하고 bubble만 사용
const String kAppModePrefsKey = 'mode';
const String kAppModeSimpleValue = 'simple';

/// 오버레이에서 사용할 UI 모드
/// - bubble  : 기존 플로팅 버블 + 글라스 패널
/// - topHalf : 상단 고정 포그라운드 UI (컨셉상 '상단 패널' 모드)
enum OverlayUIMode {
  bubble,
  topHalf,
}

class QuickOverlayApp extends StatelessWidget {
  const QuickOverlayApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: QuickOverlayHome(),
    );
  }
}

class QuickOverlayHome extends StatefulWidget {
  const QuickOverlayHome({Key? key}) : super(key: key);

  @override
  State<QuickOverlayHome> createState() => _QuickOverlayHomeState();
}

class _QuickOverlayHomeState extends State<QuickOverlayHome> with TickerProviderStateMixin {
  String _status = '대기 중';
  bool _expanded = false;
  StreamSubscription<dynamic>? _sub;

  static const _switchDuration = Duration(milliseconds: 220);

  // ───────────────────── 근무 타이머 상태 ─────────────────────
  late DateTime _overlayStartedAt;
  Duration _elapsed = Duration.zero;
  Timer? _tickTimer;

  // ───────────────────── 숨쉬기 애니메이션 (버블 전용) ─────────────────────
  late final AnimationController _breathController;
  late final Animation<double> _breathScale;

  // ───────────────────── 넛지(살짝 흔들기) 애니메이션 (버블 전용) ─────────────────────
  late final AnimationController _nudgeController;
  late final Animation<Offset> _nudgeOffset;
  Timer? _nudgeTimer;

  // ───────────────────── UI 모드(버블 / 상단) ─────────────────────
  OverlayUIMode _uiMode = OverlayUIMode.bubble;

  // ───────────────────── 앱 모드(simple이면 topHalf 금지) ─────────────────────
  bool _isSimpleMode = false;

  bool get _topHalfAllowed => !_isSimpleMode;

  // ───────────────────── "15초 쉬기" 타이머 ─────────────────────
  Timer? _shortBreakTimer;
  int _shortBreakSeq = 0;
  bool _shortBreakActive = false;

  @override
  void initState() {
    super.initState();

    // 앱 모드 로드 (mode == 'simple' 이면 topHalf 차단)
    _loadAppMode();

    _overlayStartedAt = DateTime.now();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(_overlayStartedAt);
      });
    });

    // 숨쉬기(Scale) 애니메이션 (버블용)
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

    // 넛지(살짝 오른쪽으로 툭 치는) 애니메이션 (버블용)
    _nudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _nudgeOffset = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.08, 0), // X축으로 8% 정도 이동
    ).chain(
      CurveTween(curve: Curves.easeInOut),
    ).animate(_nudgeController);

    // 1초마다 한 번씩, 접혀 있을 때만 넛지 동작
    _nudgeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_expanded && mounted && !_nudgeController.isAnimating) {
        _nudgeController.forward(from: 0.0).then((_) {
          if (mounted) {
            _nudgeController.reverse();
          }
        }).catchError((_) {});
      }
    });

    // 메인 ↔ 오버레이 데이터 수신
    _sub = FlutterOverlayWindow.overlayListener.listen((event) {
      if (!mounted) return;

      setState(() {
        // 모드 변경 메시지: "__mode:bubble__" 또는 "__mode:topHalf__"
        if (event is String && event.startsWith('__mode:')) {
          // 외부 모드 변경이 들어오면 15초 쉬기 복귀 타이머는 취소(사용자/시스템 우선)
          _cancelShortBreak();

          final raw = event.substring('__mode:'.length);

          if (raw.startsWith('topHalf')) {
            // ✅ simple 모드면 topHalf 차단 → 항상 bubble
            _uiMode = _topHalfAllowed ? OverlayUIMode.topHalf : OverlayUIMode.bubble;
          } else {
            _uiMode = OverlayUIMode.bubble;
          }
          return;
        }

        // 메인에서 '__collapse__' 를 보내면 항상 초기 상태로 접기
        if (event == '__collapse__') {
          // collapse가 들어오면 15초 쉬기 복귀 타이머도 취소
          _cancelShortBreak();

          _expanded = false;
          _status = '대기 중';
          _overlayStartedAt = DateTime.now();
          _elapsed = Duration.zero;
        } else if (event is String && event.isNotEmpty) {
          _status = event;
        } else {
          _status = '대기 중';
        }
      });
    });
  }

  /// ✅ SharedPreferences에서 mode를 읽어서 simple 여부를 결정
  /// - mode == 'simple' 이면 topHalf를 강제 차단하고 bubble로 내립니다.
  Future<void> _loadAppMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(kAppModePrefsKey); // 'simple' 등
    final isSimple = (mode == kAppModeSimpleValue);

    if (!mounted) return;
    setState(() {
      _isSimpleMode = isSimple;

      if (_isSimpleMode) {
        // simple 모드에서는 topHalf 자체가 금지이므로, 혹시라도 topHalf였으면 강제 bubble
        _cancelShortBreak();
        _uiMode = OverlayUIMode.bubble;
      }
    });
  }

  void _cancelShortBreak() {
    _shortBreakTimer?.cancel();
    _shortBreakTimer = null;
    _shortBreakActive = false;
  }

  /// ✅ "15초 쉬기"
  /// - topHalf UI를 숨기기 위해 bubble로 전환(=상단 50% 포그라운드 UI가 사라짐)
  /// - 15초 후 자동으로 topHalf UI로 복귀 (단, simple 모드에서는 복귀 금지)
  void _startShortBreak() {
    // ✅ simple 모드에서는 topHalf가 금지이므로 즉시 무시
    if (!_topHalfAllowed) return;

    // topHalf에서 눌러야 의미가 명확하므로 방어
    if (_uiMode != OverlayUIMode.topHalf) return;

    _shortBreakSeq += 1;
    final seq = _shortBreakSeq;

    _shortBreakTimer?.cancel();
    _shortBreakActive = true;

    // "휴게 중입니다" 눌렀을 때처럼 topHalf → bubble 전환 + 상태/타이머 초기화
    setState(() {
      _expanded = false;
      _status = '15초 휴게 중…';
      _overlayStartedAt = DateTime.now();
      _elapsed = Duration.zero;
      _uiMode = OverlayUIMode.bubble;
    });

    _shortBreakTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (!_shortBreakActive) return;
      if (seq != _shortBreakSeq) return; // 중복 클릭으로 갱신된 경우 무시

      setState(() {
        // ✅ 15초 후 자동 복귀: simple 모드면 topHalf 복귀 금지 → bubble 유지
        _uiMode = _topHalfAllowed ? OverlayUIMode.topHalf : OverlayUIMode.bubble;

        _shortBreakActive = false;

        _status = '휴게 종료';
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

  /// 메인 앱을 다시 여는 공통 로직
  Future<void> _launchMainApp() async {
    try {
      const intent = AndroidIntent(
        package: 'com.quintus.dev',
        componentName: 'com.quintus.dev.MainActivity',
      );

      await FlutterOverlayWindow.closeOverlay();
      await intent.launch();
      await _sendBackToMain('open_main_app');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '앱 열기 실패: $e';
        _expanded = false;
      });
    }
  }

  /// 날짜를 'YYYY-MM-DD' 형식으로 포맷
  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void _resetPanel() async {
    // 사용자가 "휴게 중입니다"를 선택했으면 15초 쉬기 자동복귀는 취소(의도 충돌 방지)
    _cancelShortBreak();

    final prefs = await SharedPreferences.getInstance();

    final String? lastBreakDate = prefs.getString(kLastBreakDatePrefsKey);
    final String? lastTopHalfResetByBreakDate = prefs.getString(kLastTopHalfResetByBreakDateKey);

    final String todayStr = _formatDate(DateTime.now());
    final bool hasRestPressedToday = (lastBreakDate == todayStr);

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
              '오늘은 아직 "휴게 사용 확인"이 기록되지 않았습니다.\n'
                  '메인 앱에서 먼저 휴게 사용을 기록해 주세요.',
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

    final bool alreadyResetOnceForToday = (lastTopHalfResetByBreakDate == lastBreakDate);

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
              '오늘 휴게 이후 상단 50% 포그라운드 모드는\n'
                  '이미 한 번 해제되었습니다.\n\n'
                  '추가로 상단 모드를 변경하려면\n'
                  '메인 앱에서 직접 설정해 주세요.',
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

    // ✅ topHalf에서만 동작 (simple 모드에서는 topHalf가 사실상 불가능하지만 방어적으로 유지)
    if (_uiMode == OverlayUIMode.topHalf) {
      setState(() {
        _status = '대기 중';
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
      return;
    }
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    } else {
      return '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 🔹 버블 모드 UI
  // ─────────────────────────────────────────────────────────────

  Widget _buildCollapsedBubble(BuildContext context) {
    return SlideTransition(
      position: _nudgeOffset,
      child: ScaleTransition(
        scale: _breathScale,
        child: Container(
          key: const ValueKey('collapsed'),
          width: kBubbleSize,
          height: kBubbleSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF4F46E5),
                Color(0xFF06B6D4),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D47A1).withOpacity(0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.menu_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _formatElapsed(_elapsed),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPanel(BuildContext context) {
    return ConstrainedBox(
      key: const ValueKey('expanded'),
      constraints: const BoxConstraints(maxWidth: kExpandedPanelWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF020617).withOpacity(0.82),
                  const Color(0xFF0F172A).withOpacity(0.88),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 18,
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white70,
                  ),
                  tooltip: '접기',
                  onPressed: () {
                    setState(() => _expanded = false);
                  },
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '근무 중 · ${_formatElapsed(_elapsed)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: _switchDuration,
                        transitionBuilder: (child, animation) {
                          final curved = CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                            reverseCurve: Curves.easeInCubic,
                          );
                          return FadeTransition(
                            opacity: curved,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.05, 0),
                                end: Offset.zero,
                              ).animate(curved),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          _status,
                          key: ValueKey(_status),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.78),
                            fontSize: 11,
                            height: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF22C55E),
                        Color(0xFF14B8A6),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22C55E).withOpacity(0.55),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 18,
                    icon: const Icon(
                      Icons.home_rounded,
                      color: Colors.white,
                    ),
                    tooltip: '앱 열기',
                    onPressed: _launchMainApp,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 🔹 상단 포그라운드 모드 UI (밝은 테마, 배경 흰색)
  // ─────────────────────────────────────────────────────────────

  Widget _buildTopHalfOverlay(BuildContext context) {
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
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth,
              ),
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
                              const Text(
                                '앱이 아직 실행 중입니다.',
                                style: TextStyle(
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
                                  children: const [
                                    TextSpan(text: '당일 근무가 끝난 분들은 꼭 '),
                                    TextSpan(
                                      text: '퇴근',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                    TextSpan(text: ' 버튼을\n눌러주시기 바랍니다.'),
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
                            color: const Color(0xFF1D4ED8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatElapsed(_elapsed),
                                style: const TextStyle(
                                  color: Colors.white,
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
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                        ),
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
                          const Text(
                            '위 항목 중 하나라도 놓쳤다면,\n'
                                '아래의 "앱으로 돌아가기" 버튼을 눌러\n'
                                '지금 바로 처리해 주세요.',
                            style: TextStyle(
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

                    // ✅ 버튼 비율: 좌/중/우 = 4 : 3 : 4
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
                            icon: const Icon(
                              Icons.timer_rounded,
                              size: 18,
                            ),
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
                            icon: const Icon(
                              Icons.refresh_rounded,
                              size: 18,
                            ),
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

  /// 체크리스트 한 줄 UI (밝은 배경용 컬러)
  Widget _buildChecklistItem({
    required IconData icon,
    required String label,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 14,
          color: const Color(0xFF4B5563),
        ),
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

  // ─────────────────────────────────────────────────────────────
  // build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ✅ 최종 표시 모드: simple 모드면 topHalf를 절대 표시하지 않음
    final effectiveMode = (_uiMode == OverlayUIMode.topHalf && _topHalfAllowed)
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
      child: SafeArea(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              onTap: () {
                if (!_expanded) {
                  setState(() => _expanded = true);
                }
              },
              child: AnimatedContainer(
                duration: _switchDuration,
                padding: _expanded ? const EdgeInsets.all(6) : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: _expanded ? kOverlayBackgroundColor.withOpacity(0.3) : Colors.transparent,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: AnimatedSwitcher(
                  duration: _switchDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    );
                    return FadeTransition(
                      opacity: curved,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.95,
                          end: 1.0,
                        ).animate(curved),
                        child: child,
                      ),
                    );
                  },
                  child: _expanded ? _buildExpandedPanel(context) : _buildCollapsedBubble(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
