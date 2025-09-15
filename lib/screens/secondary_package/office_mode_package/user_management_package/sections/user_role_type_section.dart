enum RoleType {
  dev,
  adminBillMonthly,
  adminBill,
  adminCommon,
  userLocationMonthly,
  userMonthly,
  userCommon,
  fieldCommon;

  /// 한국어 라벨 반환
  String get label {
    switch (this) {
      case RoleType.dev:
        return '개발자';
      case RoleType.adminBillMonthly:
        return '모두 열린 관리자';
      case RoleType.adminBill:
        return '정산만 열린 관리자';
      case RoleType.adminCommon:
        return '공통 관리자';
      case RoleType.userLocationMonthly:
        return '모두 열린 유저';
      case RoleType.userMonthly:
        return '정기 주차만 열린 유저';
      case RoleType.userCommon:
        return '공통 유저';
      case RoleType.fieldCommon:
        return '공통 필드';
    }
  }

  /// 이름 문자열에서 RoleType enum으로 변환
  static RoleType fromName(String name) {
    return RoleType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => RoleType.fieldCommon,
    );
  }
}
