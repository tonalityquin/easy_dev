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
}
