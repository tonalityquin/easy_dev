enum TabletRoleType {
  dev, // 개발자
  admin, // 관리자 (전반)
  ceo, // 대표자
  highManager, // 상급 관리
  middleManager, // 중급 관리
  lowManager, // 하급 관리
  highField, // 상급 필드
  middleField, // 중급 필드
  lowField; // 하급 필드

  /// 한국어 라벨 반환
  String get label {
    switch (this) {
      case TabletRoleType.dev:
        return '개발자';
      case TabletRoleType.admin:
        return '관리자';
      case TabletRoleType.ceo:
        return '대표자';
      case TabletRoleType.highManager:
        return '상급 관리';
      case TabletRoleType.middleManager:
        return '중급 관리';
      case TabletRoleType.lowManager:
        return '하급 관리';
      case TabletRoleType.highField:
        return '상급 필드';
      case TabletRoleType.middleField:
        return '중급 필드';
      case TabletRoleType.lowField:
        return '하급 필드';
    }
  }

  /// 이름 문자열에서 RoleType enum으로 변환
  static TabletRoleType fromName(String name) {
    return TabletRoleType.values.firstWhere(
          (e) => e.name == name,
      orElse: () => TabletRoleType.lowField,
    );
  }

  /// 라벨 문자열에서 RoleType enum으로 변환
  static TabletRoleType fromLabel(String label) {
    return TabletRoleType.values.firstWhere(
          (e) => e.label == label,
      orElse: () => TabletRoleType.lowField,
    );
  }
}

extension RoleTypeExtension on TabletRoleType {
  /// 관리자/내근직 그룹 판별
  bool get isManager => [
    TabletRoleType.lowManager,
    TabletRoleType.middleManager,
    TabletRoleType.highManager,
    TabletRoleType.admin,
    TabletRoleType.ceo,
  ].contains(this);

  /// 필드직 그룹 판별
  bool get isField => [
    TabletRoleType.lowField,
    TabletRoleType.middleField,
    TabletRoleType.highField,
  ].contains(this);

  /// 최상위 권한 여부
  bool get isDeveloper => this == TabletRoleType.dev;
}
