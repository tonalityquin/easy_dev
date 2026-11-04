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
