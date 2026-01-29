import 'package:flutter/material.dart';

enum RoleType {
  dev,
  adminBillMonthly,
  adminBillMonthlyTablet,
  adminBill,
  adminBillTablet,
  adminCommon,
  adminCommonTablet,
  userLocationMonthly,
  userMonthly,
  userCommon,
  fieldCommon;

  /// 한국어 라벨 반환
  String get label {
    switch (this) {
      case RoleType.dev:
        return '개발자(태블릿 O)';
      case RoleType.adminBillMonthly:
        return '모두 열린 관리자(태블릿 X)';
      case RoleType.adminBillMonthlyTablet:
        return '모두 열린 관리자(태블릿 O)';
      case RoleType.adminBill:
        return '정산만 열린 관리자(태블릿 X)';
      case RoleType.adminBillTablet:
        return '정산만 열린 관리자(태블릿 O)';
      case RoleType.adminCommon:
        return '공통 관리자(태블릿 X)';
      case RoleType.adminCommonTablet:
        return '공통 관리자(태블릿 O)';
      case RoleType.userLocationMonthly:
        return '모두 열린 유저(태블릿 X)';
      case RoleType.userMonthly:
        return '정기 주차만 열린 유저(태블릿 X)';
      case RoleType.userCommon:
        return '공통 유저(태블릿 X)';
      case RoleType.fieldCommon:
        return '공통 필드(태블릿 X)';
    }
  }

  /// ✅ 브랜드테마(ColorScheme) 기반 "역할 배지" 스타일
  ///
  /// - UI에서 Chip/Badge를 만들 때 사용하세요.
  /// - RoleType 자체는 UI 의존을 갖지 않는 게 정석이지만,
  ///   현재 요청이 "브랜드테마 적용"이므로, 안전하게 선택적으로 쓰도록
  ///   theme helper를 제공하는 형태로 추가했습니다.
  ///
  /// 사용 예:
  ///   final cs = Theme.of(context).colorScheme;
  ///   Chip(
  ///     label: Text(role.label),
  ///     backgroundColor: role.badgeBackground(cs),
  ///     labelStyle: TextStyle(color: role.badgeForeground(cs), fontWeight: FontWeight.w800),
  ///   )
  Color badgeBackground(ColorScheme cs) {
    if (this == RoleType.dev) return cs.tertiaryContainer;
    if (isAdmin) return cs.primaryContainer;
    if (hasMonthly) return cs.secondaryContainer;
    return cs.surfaceVariant;
  }

  Color badgeForeground(ColorScheme cs) {
    if (this == RoleType.dev) return cs.onTertiaryContainer;
    if (isAdmin) return cs.onPrimaryContainer;
    if (hasMonthly) return cs.onSecondaryContainer;
    return cs.onSurfaceVariant;
  }

  /// ✅ UX 분류용 헬퍼(테마와 무관하지만 배지/필터 등에 유용)
  bool get isAdmin {
    switch (this) {
      case RoleType.adminBillMonthly:
      case RoleType.adminBillMonthlyTablet:
      case RoleType.adminBill:
      case RoleType.adminBillTablet:
      case RoleType.adminCommon:
      case RoleType.adminCommonTablet:
        return true;
      default:
        return false;
    }
  }

  bool get hasMonthly {
    switch (this) {
      case RoleType.adminBillMonthly:
      case RoleType.adminBillMonthlyTablet:
      case RoleType.userLocationMonthly:
      case RoleType.userMonthly:
        return true;
      default:
        return false;
    }
  }

  bool get supportsTablet {
    switch (this) {
      case RoleType.dev:
      case RoleType.adminBillMonthlyTablet:
      case RoleType.adminBillTablet:
      case RoleType.adminCommonTablet:
        return true;
      default:
        return false;
    }
  }
}
