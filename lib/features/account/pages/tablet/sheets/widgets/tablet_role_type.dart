enum TabletRoleType {
  dev, 
  admin, 
  ceo, 
  highManager, 
  middleManager, 
  lowManager, 
  highField, 
  middleField, 
  lowField; 

  
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

  
  static TabletRoleType fromName(String name) {
    return TabletRoleType.values.firstWhere(
          (e) => e.name == name,
      orElse: () => TabletRoleType.lowField,
    );
  }

  
  static TabletRoleType fromLabel(String label) {
    return TabletRoleType.values.firstWhere(
          (e) => e.label == label,
      orElse: () => TabletRoleType.lowField,
    );
  }
}

extension RoleTypeExtension on TabletRoleType {
  
  bool get isManager => [
    TabletRoleType.lowManager,
    TabletRoleType.middleManager,
    TabletRoleType.highManager,
    TabletRoleType.admin,
    TabletRoleType.ceo,
  ].contains(this);

  
  bool get isField => [
    TabletRoleType.lowField,
    TabletRoleType.middleField,
    TabletRoleType.highField,
  ].contains(this);

  
  bool get isDeveloper => this == TabletRoleType.dev;
}
