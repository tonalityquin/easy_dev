import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import 'sprint_workspace_home_page.dart';

class SprintModeLoadingPage extends StatefulWidget {
  const SprintModeLoadingPage({
    super.key,
    this.returnRouteName,
  });

  final String? returnRouteName;

  @override
  State<SprintModeLoadingPage> createState() => _SprintModeLoadingPageState();
}

class _SprintModeLoadingPageState extends State<SprintModeLoadingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final SprintModeStore _store;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _store = SprintModeStore();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await _store.initialize();
      if (!mounted) return;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          settings: const RouteSettings(name: '/sprint_mode_workspace'),
          transitionDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 320),
          reverseTransitionDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 240),
          pageBuilder: (_, __, ___) => SprintWorkspaceHomePage(
            store: _store,
            returnRouteName: widget.returnRouteName,
          ),
          transitionsBuilder: (_, animation, __, child) {
            if (reduceMotion) return child;
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.025),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (_error != null) _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colors.surface,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      if (reduceMotion) return child!;
                      final value = Curves.easeInOut.transform(
                        _pulseController.value,
                      );
                      return Transform.scale(
                        scale: 0.97 + value * 0.06,
                        child: Opacity(
                          opacity: 0.78 + value * 0.22,
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Icon(
                        Icons.bolt_rounded,
                        size: 46,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    _error == null
                        ? '로컬 데이터를 불러오는 중'
                        : '로컬 데이터를 불러오지 못했습니다.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (_error == null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 180,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: const LinearProgressIndicator(minHeight: 5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
