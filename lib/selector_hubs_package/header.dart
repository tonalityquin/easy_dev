// lib/screens/selector_hubs_package/header.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class Header extends StatefulWidget {
  const Header({super.key});

  @override
  State<Header> createState() => _HeaderState();
}

class _HeaderState extends State<Header> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        _TopRow(
          expanded: _expanded,
          onToggle: _toggleExpanded,
        ),
        const SizedBox(height: 12),
        Text(
          '환영합니다',
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          '화살표 버튼을 누르면 해당 페이지로 진입합니다.',
          style: text.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 상단 가로 레이아웃: [왼쪽 버튼(설정)] [배지(아이콘)] [오른쪽 버튼(앱 종료)]
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  // 앱 종료 처리:
  // 1) Android: flutter_foreground_task 서비스가 실행 중이면 중지 → 앱 종료
  // 2) 그 외: 바로 앱 종료 (iOS는 정책상 완전 종료가 보장되지 않을 수 있음)
  Future<void> _exitApp(BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        bool running = false;
        try {
          running = await FlutterForegroundTask.isRunningService;
        } catch (_) {
          // 일부 기기/버전에서 isRunningService 호출 실패해도 종료는 계속
        }

        if (running) {
          try {
            final stopped = await FlutterForegroundTask.stopService();
            if (stopped != true) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('포그라운드 중지 실패(플러그인 반환값 false)')),
              );
            }
          } catch (e) {
            // 여기서 예외가 나도 앱 종료는 시도
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('포그라운드 중지 실패: $e')),
            );
          }
          // 서비스 중지 요청 후 약간의 여유
          await Future.delayed(const Duration(milliseconds: 150));
        }

        await SystemNavigator.pop(); // 태스크 종료
      } else {
        await SystemNavigator.pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('앱 종료 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const double sideWidth = 120;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 왼쪽: 설정 (기능 미구현)
        _AnimatedSide(
          show: expanded,
          width: sideWidth,
          child: FilledButton.icon(
            onPressed: () {
              // TODO: 설정 화면 연결 예정
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('설정은 준비 중입니다.')),
              );
            },
            icon: const Icon(Icons.settings_outlined),
            label: const Text('설정'),
          ),
        ),
        const SizedBox(width: 12),

        // 중앙 배지(아이콘). 탭하면 회전 + onToggle 호출로 좌/우 버튼 토글
        HeaderBadge(size: 64, ring: 3, onToggle: onToggle),

        const SizedBox(width: 12),

        // 오른쪽: 앱 종료 (포그라운드 서비스까지 종료)
        _AnimatedSide(
          show: expanded,
          width: sideWidth,
          child: FilledButton.icon(
            onPressed: () async => _exitApp(context),
            icon: const Icon(Icons.power_settings_new),
            label: const Text('앱 종료'),
          ),
        ),
      ],
    );
  }
}

/// 좌/우 버튼의 등장/퇴장 애니메이션(가로폭 + 투명도)
class _AnimatedSide extends StatelessWidget {
  const _AnimatedSide({
    required this.show,
    required this.width,
    required this.child,
  });

  final bool show;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // AnimatedSize 대신 AnimatedContainer로 폭 애니메이션(간단·안정)
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      width: show ? width : 0,
      child: AnimatedOpacity(
        opacity: show ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: show ? child : const SizedBox.shrink(),
      ),
    );
  }
}

class HeaderBadge extends StatelessWidget {
  const HeaderBadge({
    super.key,
    this.size = 64,
    this.ring = 3,
    this.onToggle,
  });

  final double size;
  final double ring;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: .92, end: 1),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
          ),
          child: Padding(
            padding: EdgeInsets.all(ring),           // ring 값 적용
            child: _HeaderBadgeInner(onToggle: onToggle), // 콜백 전달
          ),
        ),
      ),
    );
  }
}

class _HeaderBadgeInner extends StatefulWidget {
  const _HeaderBadgeInner({this.onToggle});

  final VoidCallback? onToggle;

  @override
  State<_HeaderBadgeInner> createState() => _HeaderBadgeInnerState();
}

class _HeaderBadgeInnerState extends State<_HeaderBadgeInner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotCtrl;

  @override
  void initState() {
    super.initState();
    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // 회전 시간
    );
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _rotCtrl.forward(from: 0);     // 360도 회전
    widget.onToggle?.call();       // 좌/우 버튼 토글
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 배지 전체 탭 → 회전 + 토글
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onTap,
                  child: Center(
                    child: RotationTransition(
                      turns: Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _rotCtrl,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                      child: const Icon(
                        Icons.dashboard_customize_rounded,
                        color: Colors.black,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),

              // 빛 반사 하이라이트(탭 방해 X)
              Positioned(
                top: cons.maxHeight * 0.12,
                left: cons.maxWidth * 0.22,
                right: cons.maxWidth * 0.22,
                child: IgnorePointer(
                  child: Container(
                    height: cons.maxHeight * 0.18,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
