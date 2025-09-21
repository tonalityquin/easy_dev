// lib/screens/selector_hubs_package/header.dart
import 'package:flutter/material.dart';

class Header extends StatelessWidget {
  const Header({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        const HeaderBadge(size: 64, ring: 3),
        const SizedBox(height: 12),
        Text('환영합니다',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('화살표 버튼을 누르면 해당 페이지로 진입합니다.',
            style: text.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
            textAlign: TextAlign.center),
      ],
    );
  }
}

class HeaderBadge extends StatelessWidget {
  const HeaderBadge({super.key, this.size = 64, this.ring = 3});
  final double size;
  final double ring;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: .92, end: 1),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: SizedBox(
        width: size, height: size,
        child: DecoratedBox(
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
          child: Padding(
            padding: EdgeInsets.all(ring),
            child: const _HeaderBadgeInner(),
          ),
        ),
      ),
    );
  }
}

class _HeaderBadgeInner extends StatelessWidget {
  const _HeaderBadgeInner();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white, shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8, offset: const Offset(0, 4),
            )],
          ),
          child: Stack(
            children: [
              const Center(child: Icon(Icons.dashboard_customize_rounded,
                  color: Colors.black, size: 28)),
              Positioned(
                top: cons.maxHeight * 0.12,
                left: cons.maxWidth * 0.22,
                right: cons.maxWidth * 0.22,
                child: Container(
                  height: cons.maxHeight * 0.18,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(20),
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
