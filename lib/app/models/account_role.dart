enum RoleType {
  ceo,
  headAdmin,
  headStaff,
  branchAdmin,
  branchProAdmin,
  branchStaff,
  branchProStaff;

  String get label => switch (this) {
    RoleType.ceo => '대표자',
    RoleType.headAdmin => '본사 관리자',
    RoleType.headStaff => '본사 직원',
    RoleType.branchAdmin => '지사 관리자',
    RoleType.branchProAdmin => '지사 심화 관리자',
    RoleType.branchStaff => '지사 직원',
    RoleType.branchProStaff => '지사 심화 직원',
  };

  static RoleType? fromName(String? name) {
    if (name == null) return null;
    for (final role in RoleType.values) {
      if (role.name == name.trim()) return role;
    }
    return null;
  }

  bool get isHeadOffice =>
      this == RoleType.ceo ||
      this == RoleType.headAdmin ||
      this == RoleType.headStaff;

  bool get canManageAccounts =>
      isHeadOffice || this == RoleType.branchProAdmin;

  bool get hasManagementMenu =>
      isHeadOffice ||
      this == RoleType.branchProAdmin ||
      this == RoleType.branchProStaff;

  bool get usesFieldScreen =>
      this == RoleType.branchAdmin ||
      this == RoleType.branchStaff ||
      this == RoleType.branchProStaff;

  bool get canDeleteOtherVoice =>
      this == RoleType.ceo ||
      this == RoleType.headAdmin ||
      this == RoleType.branchProAdmin;
}
