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

class _QuickOverlayHomeState extends State<QuickOverlayHome>
    with TickerProviderStateMixin {
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

  // ───────────────────── 오버레이 형태 선택 카드 활성화 조건 ─────────────────────
  // division / selectedArea 가 비어 있지 않고, 두 값이 서로 같을 때만 true
  bool _overlayModeCardEnabled = false;

  @override
  void initState() {
    super.initState();

    _overlayStartedAt = DateTime.now();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(_overlayStartedAt);
      });
    });

    // 🔹 division / selectedArea 기반으로 오버레이 형태 선택 카드 사용 가능 여부 로드
    _initOverlayModeCardEnabled();

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
    )
        .chain(
      CurveTween(curve: Curves.easeInOut),
    )
        .animate(_nudgeController);

    // 1초마다 한 번씩, 접혀 있을 때만 넛지 동작
    _nudgeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_expanded && mounted && !_nudgeController.isAnimating) {
        _nudgeController.forward(from: 0.0).then((_) {
          if (mounted) {
            _nudgeController.reverse();
          }
        }).catchError((_) {
          // dispose 중 등 애니메이션 도중 에러는 무시
        });
      }
    });

    // 메인 ↔ 오버레이 데이터 수신
    _sub = FlutterOverlayWindow.overlayListener.listen((event) {
      if (!mounted) return;
      setState(() {
        // 모드 변경 메시지: "__mode:bubble__" 또는 "__mode:topHalf__"
        if (event is String && event.startsWith('__mode:')) {
          final raw = event.substring('__mode:'.length);
          if (raw.startsWith('topHalf')) {
            // ✅ division / selectedArea 조건을 만족하는 경우에만
            //    상단 50% 포그라운드 모드로 전환을 허용
            if (_overlayModeCardEnabled) {
              _uiMode = OverlayUIMode.topHalf;
            } else {
              // 조건을 만족하지 않으면 항상 버블 모드 유지
              _uiMode = OverlayUIMode.bubble;
            }
          } else {
            _uiMode = OverlayUIMode.bubble;
          }
          return;
        }

        // 메인에서 '__collapse__' 를 보내면 항상 초기 상태로 접기
        if (event == '__collapse__') {
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

  /// SharedPreferences 에서 division / selectedArea 를 불러와
  /// 오버레이 형태 선택 카드 사용 가능 여부를 판별
  Future<void> _initOverlayModeCardEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final division = prefs.getString('division') ?? '';
    final selectedArea = prefs.getString('selectedArea') ?? '';

    final enabled = division.isNotEmpty &&
        selectedArea.isNotEmpty &&
        division == selectedArea;

    if (!mounted) return;
    setState(() {
      _overlayModeCardEnabled = enabled;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tickTimer?.cancel();
    _nudgeTimer?.cancel();
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

  /// 패널 상태/타이머 초기화 + SharedPreferences 기준 모드 전환
  ///
  /// - SharedPreferences 에서 'last_break_date' 값을 읽는다.
  /// - 오늘 날짜와 저장된 날짜가 다르다면(= 오늘 휴게 버튼을 누르지 않았다면):
  ///     상단(포그라운드) 모드에서 → 버블 모드로 전환 + 상태/타이머 초기화
  /// - 오늘 이미 눌렀다면: 안내 다이얼로그로 이유를 알려줌
  void _resetPanel() async {
    final prefs = await SharedPreferences.getInstance();

    // 메인 앱에서 휴게 버튼 성공 시 저장한 'YYYY-MM-DD' 문자열
    final String? lastBreakDate = prefs.getString(kLastBreakDatePrefsKey);
    final String todayStr = _formatDate(DateTime.now());

    final bool hasRestPressedToday = (lastBreakDate == todayStr);

    // 오늘 휴게 버튼을 안 눌렀고, 현재 상단 모드일 때만 동작
    if (!hasRestPressedToday && _uiMode == OverlayUIMode.topHalf) {
      setState(() {
        _status = '대기 중';
        _overlayStartedAt = DateTime.now();
        _elapsed = Duration.zero;

        // 상단 50% 포그라운드 → 플로팅 버블 모드로 전환
        _uiMode = OverlayUIMode.bubble;
      });
      return;
    }

    // 🔹 이미 오늘 휴게를 눌렀다면 → 왜 변화가 없는지 간단히 알려주기
    if (hasRestPressedToday && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D4ED8).withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.free_breakfast_rounded,
                    size: 20,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '오늘 휴게 사용 완료',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              '오늘은 이미 휴게 사용이 기록되어 있어\n'
                  '추가로 확인할 휴게 내역이 없습니다.',
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

  // 접힌 상태: 동그란 버블 + 타이머
  Widget _buildCollapsedBubble(BuildContext context) {
    return SlideTransition(
      position: _nudgeOffset, // ← 넛지(좌우 살짝 이동)
      child: ScaleTransition(
        scale: _breathScale, // ← 숨쉬기(살짝 커졌다 작아졌다)
        child: Container(
          key: const ValueKey('collapsed'),
          width: kBubbleSize,
          height: kBubbleSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF4F46E5), // indigo
                Color(0xFF06B6D4), // cyan
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
            // 전체를 FittedBox로 감싸서 작은 버블 안에서도 오버플로우 없도록
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

  // 펼친 상태: 글라스 패널 + 타이머 + 앱 열기 버튼
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
                // ⬅ 접기
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

                // 상태 + 타이머
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

                // 🔸 앱 열기 버튼
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
  //
  //   - FittedBox(BoxFit.scaleDown) 로 전체 레이아웃을 비율 축소
  //   - 작은 기기에서도 overflow 없이 전체 내용 표시
  // ─────────────────────────────────────────────────────────────

  Widget _buildTopHalfOverlay(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          color: Colors.white, // 전체 배경을 흰색으로
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
                    // ───── 상단 헤더: 안내 문구 + 경과 시간 뱃지 ─────
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
                                  color: Color(0xFF111827), // 거의 검정에 가까운 딥그레이
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text.rich(
                                TextSpan(
                                  style: const TextStyle(
                                    color: Color(0xFF4B5563), // 기본 회색 계열
                                    fontSize: 11,
                                  ),
                                  children: const [
                                    TextSpan(
                                      text: '당일 근무가 끝난 분들은 꼭 ',
                                    ),
                                    TextSpan(
                                      text: '퇴근',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700, // 굵게
                                        color: Color(0xFFDC2626), // 🔴 붉은색 강조
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
                            color: const Color(0xFF1D4ED8), // 파란색 뱃지
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

                    // ───── 오늘 마무리 체크리스트 (밝은 카드) ─────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: const Color(0xFFF9FAFB), // 아주 옅은 회색 배경
                        border: Border.all(
                          color: const Color(0xFFE5E7EB), // 연한 테두리
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

                          // ─── 공통 체크 그룹 ───
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

                          // ─── 인계/보고 체크 그룹 ───
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

                          // 🔸 체크리스트 강조 문구 (메인 앱 이동 유도)
                          const SizedBox(height: 10),
                          const Text(
                            '위 항목 중 하나라도 놓쳤다면,\n'
                                '아래의 "앱으로 돌아가기" 버튼을 눌러\n'
                                '지금 바로 처리해 주세요.',
                            style: TextStyle(
                              color: Color(0xFFF97316), // 주황 계열 강조 색
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ───── 빠른 액션 버튼 두 개 ─────
                    Row(
                      children: [
                        // 1) 메인 앱 이동 (Primary)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _launchMainApp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF111827), // 진한 색상
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
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
                        // 2) 휴게시간 확인 버튼 (Secondary)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _resetPanel,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF111827),
                              side: const BorderSide(
                                color: Color(0xFF9CA3AF),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
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
          color: const Color(0xFF4B5563), // 아이콘: 중간 회색
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF374151), // 텍스트: 진한 회색
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
    // 👉 상단 포그라운드 모드일 때: 밝은 테마의 전용 UI 사용
    if (_uiMode == OverlayUIMode.topHalf) {
      return Material(
        color: Colors.transparent,
        child: _buildTopHalfOverlay(context),
      );
    }

    // 👉 기본 모드: 플로팅 버블 + 글라스 패널 (어두운 테마 유지)
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
                  color: _expanded
                      ? kOverlayBackgroundColor.withOpacity(0.3)
                      : Colors.transparent,
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
                  child: _expanded
                      ? _buildExpandedPanel(context)
                      : _buildCollapsedBubble(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
