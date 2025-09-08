enum RoleType {
  dev,            // 개발자
  admin,          // 관리자 (전반)
  ceo,            // 대표자
  highManager,    // 상급 관리
  middleManager,  // 중급 관리
  lowManager,     // 하급 관리
  highField,      // 상급 필드
  middleField,    // 중급 필드
  lowField;       // 하급 필드

  /// 한국어 라벨 반환
  String get label {
    switch (this) {
      case RoleType.dev:
        return '개발자';
      case RoleType.admin:
        return '관리자';
      case RoleType.ceo:
        return '대표자';
      case RoleType.highManager:
        return '상급 관리';
      case RoleType.middleManager:
        return '중급 관리';
      case RoleType.lowManager:
        return '하급 관리';
      case RoleType.highField:
        return '상급 필드';
      case RoleType.middleField:
        return '중급 필드';
      case RoleType.lowField:
        return '하급 필드';
    }
  }

  /// 이름 문자열에서 RoleType enum으로 변환
  static RoleType fromName(String name) {
    return RoleType.values.firstWhere(
          (e) => e.name == name,
      orElse: () => RoleType.lowField,
    );
  }

  /// 라벨 문자열에서 RoleType enum으로 변환
  static RoleType fromLabel(String label) {
    return RoleType.values.firstWhere(
          (e) => e.label == label,
      orElse: () => RoleType.lowField,
    );
  }
}

extension RoleTypeExtension on RoleType {
  /// 관리자/내근직 그룹 판별
  bool get isManager => [
    RoleType.lowManager,
    RoleType.middleManager,
    RoleType.highManager,
    RoleType.admin,
    RoleType.ceo,
  ].contains(this);

  /// 필드직 그룹 판별
  bool get isField => [
    RoleType.lowField,
    RoleType.middleField,
    RoleType.highField,
  ].contains(this);

  /// 최상위 권한 여부
  bool get isDeveloper => this == RoleType.dev;
}
