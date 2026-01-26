import 'package:flutter/material.dart';

/// 경위서/보고서/서명 화면에서 공통으로 사용하는 버튼 스타일 모음
/// - 하드코딩 팔레트 제거
/// - ColorScheme 기반으로 전역 프리셋/다크모드를 자동 반영
class SingleReportButtonStyles {
  static const double _radius = 8.0;

  /// 메인 액션 버튼
  static ButtonStyle primary(
      BuildContext context, {
        double minHeight = 55,
      }) {
    final cs = Theme.of(context).colorScheme;

    return ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      minimumSize: Size(0, minHeight),
      padding: EdgeInsets.zero,
      side: BorderSide(
        color: cs.primary,
        width: 1.0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      elevation: 0,
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed) ? cs.primary.withOpacity(.12) : null,
      ),
    );
  }

  /// 서브/보조 액션 버튼
  static ButtonStyle outlined(
      BuildContext context, {
        double minHeight = 55,
      }) {
    final cs = Theme.of(context).colorScheme;

    return OutlinedButton.styleFrom(
      foregroundColor: cs.onSurface,
      backgroundColor: cs.surface,
      side: BorderSide(
        color: cs.outlineVariant,
        width: 1.0,
      ),
      minimumSize: Size(0, minHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed) ? cs.outlineVariant.withOpacity(.18) : null,
      ),
    );
  }

  static ButtonStyle smallPrimary(BuildContext context) => primary(context, minHeight: 44);

  static ButtonStyle smallOutlined(BuildContext context) => outlined(context, minHeight: 44);
}
