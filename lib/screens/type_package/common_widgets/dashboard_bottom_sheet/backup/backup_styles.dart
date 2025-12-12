// lib/screens/simple_package/simple_inside_package/sections/simple_inside_report_styles.dart

import 'package:flutter/material.dart';

/// 경위서 화면 전용 컬러 팔레트
/// DocumentType.statementForm 의 기본 색상(0xFF8D6E63)을 기준으로 구성
class BackupColors {
  /// 기본 브라운 (statementForm 기준 색)
  static const Color base = Color(0xFF8D6E63); // primary

  /// base 보다 어두운 브라운 (강조 텍스트/아이콘)
  static const Color dark = Color(0xFF6D4C41); // 강조 텍스트/아이콘

  /// base 를 옅게 사용한 톤 (보더/톤 변형)
  static const Color light = Color(0xFFD7CCC8); // 톤 변형/보더

  /// 전경(아이콘/텍스트)
  static const Color fg = Color(0xFFFFFFFF); // 전경(아이콘/텍스트)
}

/// 경위서 화면에서 공통으로 사용하는 버튼 스타일 모음
class BackupButtonStyles {
  static const double _radius = 8.0;

  /// 메인 액션 버튼
  static ButtonStyle primary({double minHeight = 55}) {
    return ElevatedButton.styleFrom(
      backgroundColor: BackupColors.base,
      foregroundColor: BackupColors.fg,
      minimumSize: Size(0, minHeight),
      padding: EdgeInsets.zero,
      side: const BorderSide(
        color: BackupColors.dark,
        width: 1.0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      elevation: 0,
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) =>
        states.contains(MaterialState.pressed) ? BackupColors.dark.withOpacity(.10) : null,
      ),
    );
  }

  /// 서브/보조 액션 버튼1
  static ButtonStyle outlined({double minHeight = 55}) {
    return OutlinedButton.styleFrom(
      foregroundColor: BackupColors.dark,
      backgroundColor: Colors.white,
      side: const BorderSide(
        color: BackupColors.light,
        width: 1.0,
      ),
      minimumSize: Size(0, minHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) =>
        states.contains(MaterialState.pressed) ? BackupColors.light.withOpacity(.16) : null,
      ),
    );
  }

  static ButtonStyle smallPrimary() => primary(minHeight: 44);

  static ButtonStyle smallOutlined() => outlined(minHeight: 44);
}
