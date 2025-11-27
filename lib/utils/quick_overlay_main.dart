// lib/utils/quick_overlay_main.dart
import 'dart:async';
import 'dart:ui'; // 글라스(blur) 효과용

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:android_intent_plus/android_intent.dart';

/// 오버레이 전체 배경 색상 (글라스 박스에만 사용)
const Color kOverlayBackgroundColor = Color(0xFF020617);

/// 내부 UI 레이아웃 사이즈들 (윈도우보다 살짝 작게)
const double kBubbleSize = 56.0;
const double kExpandedPanelWidth = 280.0;

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

  // ───────────────────── 숨쉬기 애니메이션 ─────────────────────
  late final AnimationController _breathController;
  late final Animation<double> _breathScale;

  // ───────────────────── 넛지(살짝 흔들기) 애니메이션 ─────────────────────
  late final AnimationController _nudgeController;
  late final Animation<Offset> _nudgeOffset;
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();

    _overlayStartedAt = DateTime.now();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsed = DateTime.now().difference(_overlayStartedAt);
      });
    });

    // 숨쉬기(Scale) 애니메이션
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

    // 넛지(살짝 오른쪽으로 툭 치는) 애니메이션
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
      setState(() {
        if (event == '__collapse__') {
          // 메인에서 '__collapse__' 를 보내면 항상 초기 상태로 접기
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

  // 🔹 접힌 상태: 동그란 버블 + 타이머
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
    );
  }

  // 🔹 펼친 상태: 글라스 패널 + 타이머 + 앱 열기 버튼
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
                    onPressed: () async {
                      try {
                        const intent = AndroidIntent(
                          package: 'com.quintus.dev',
                          componentName: 'com.quintus.dev.MainActivity',
                        );

                        await FlutterOverlayWindow.closeOverlay();
                        await intent.launch();
                        await _sendBackToMain('open_main_app');
                      } catch (e) {
                        setState(() {
                          _status = '앱 열기 실패: $e';
                          _expanded = false;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 👉 오버레이 윈도우 전체는 항상 투명.
    //    - enableDrag 로 윈도우 자체를 끌어다니고
    //    - 이 안에서는 왼쪽 가운데에 고정된 버블/패널만 렌더링.
    //    - _expanded == true 일 때만 주변에 반투명 배경 박스를 깔아준다.
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
