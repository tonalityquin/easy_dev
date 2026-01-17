import 'package:flutter/material.dart';

/// 경위서 화면 전용 컬러 팔레트
class SingleReportColors {
  static const Color base = Color(0xFF00897B); // primary
  static const Color dark = Color(0xFF00695C); // 강조 텍스트/아이콘
  static const Color light = Color(0xFF80CBC4); // 톤 변형/보더
  static const Color fg = Color(0xFFFFFFFF); // 전경(아이콘/텍스트)
}

/// 경위서 화면에서 공통으로 사용하는 버튼 스타일 모음
class SingleReportButtonStyles {
  static const double _radius = 8.0;

  /// 메인 액션 버튼
  static ButtonStyle primary({double minHeight = 55}) {
    return ElevatedButton.styleFrom(
      backgroundColor: SingleReportColors.base,
      foregroundColor: SingleReportColors.fg,
      minimumSize: Size(0, minHeight),
      padding: EdgeInsets.zero,
      side: const BorderSide(
        color: SingleReportColors.dark,
        width: 1.0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      elevation: 0,
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
        (states) => states.contains(MaterialState.pressed) ? SingleReportColors.dark.withOpacity(.10) : null,
      ),
    );
  }

  /// 서브/보조 액션 버튼
  static ButtonStyle outlined({double minHeight = 55}) {
    return OutlinedButton.styleFrom(
      foregroundColor: SingleReportColors.dark,
      backgroundColor: Colors.white,
      side: const BorderSide(
        color: SingleReportColors.light,
        width: 1.0,
      ),
      minimumSize: Size(0, minHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
        (states) => states.contains(MaterialState.pressed) ? SingleReportColors.light.withOpacity(.16) : null,
      ),
    );
  }

  static ButtonStyle smallPrimary() => primary(minHeight: 44);

  static ButtonStyle smallOutlined() => outlined(minHeight: 44);
}
