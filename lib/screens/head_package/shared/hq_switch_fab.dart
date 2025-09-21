// lib/screens/head_package/shared/hq_switch_fab.dart
import 'package:flutter/material.dart';

/// 본사 화면 간 상호 이동을 위한 공용 FAB 위젯.
/// - 이 파일 안에 HR 팔레트(blue 800/900/200)를 정의하고,
///   기본 배경/전경색으로 사용합니다.
/// - 두 페이지(HeadquarterPage, HeadStubPage)에서 동일 위치(endFloat)에 배치해
///   일관된 UX를 제공합니다.
class HqSwitchFab extends StatelessWidget {
  const HqSwitchFab({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,   // 지정 시 내부 팔레트보다 우선
    this.foregroundColor,   // 지정 시 내부 팔레트보다 우선
    this.tooltip,
    this.wideThreshold = 520,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final String? tooltip;
  final double wideThreshold;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= wideThreshold;

    // 👉 내부 팔레트 기본값 적용 (필요 시 파라미터로 덮어쓰기 가능)
    final Color bg = backgroundColor ?? _HqPalette.hrBase;   // blue 800
    final Color fg = foregroundColor ?? Colors.white;        // 대비용

    final Widget fabChild = isWide
        ? FloatingActionButton.extended(
      onPressed: onPressed,
      label: Text(label),
      icon: Icon(icon),
      backgroundColor: bg,
      foregroundColor: fg,
    )
        : FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: bg,
      foregroundColor: fg,
      child: Icon(icon),
    );

    return Tooltip(
      message: tooltip ?? label,
      child: Semantics(
        button: true,
        label: label,
        child: fabChild,
      ),
    );
  }
}

/// HQ 공용 팔레트 (FAB 기본 색으로 사용)
class _HqPalette {
  // HR(관리) — Blue
  static const Color hrBase  = Color(0xFF1565C0); // blue 800
}
