class StaffAccessPolicy {
  const StaffAccessPolicy._();

  static const List<String> baseRoles = <String>[
    'fieldCommon',
    'userCommon',
    'specialist',
    'areaManager',
    'divisionManager',
    'superAdmin',
  ];

  static const Map<String, String> roleLabels = <String, String>{
    'fieldCommon': '현장 일반 직원',
    'userCommon': '일반 직원',
    'specialist': '전문 업무 담당자',
    'areaManager': '지역 관리자',
    'divisionManager': '회사 관리자',
    'superAdmin': '최고 관리자',
  };

  static const Map<String, String> profileLabels = <String, String>{
    'none': '관리 권한 없음',
    'monthlyOnly': '정기주차',
    'monthlyLocation': '정기주차 · 구역',
    'billingOnly': '정산',
    'operationsCore': '계정 · 섹터 · 구역 · 규칙',
    'operationsTablet': '기본 관리 · 태블릿',
    'operationsBilling': '기본 관리 · 정산',
    'operationsBillingTablet': '기본 관리 · 정산 · 태블릿',
    'operationsBillingMonthly': '기본 관리 · 정산 · 정기주차',
    'operationsAll': '기본 관리 · 정산 · 정기주차 · 태블릿',
    'generalAll': '모든 일반 업무 및 관리',
  };

  static const Map<String, Set<String>> profilePermissions = <String, Set<String>>{
    'none': <String>{},
    'monthlyOnly': <String>{'monthly.manage'},
    'monthlyLocation': <String>{'monthly.manage', 'location.manage'},
    'billingOnly': <String>{'bill.manage'},
    'operationsCore': <String>{
      'accounts.read', 'accounts.create', 'accounts.update', 'accounts.delete',
      'accounts.activate', 'accounts.assignRole',
      'sector.manage', 'location.manage', 'rule.manage',
      'voice.delete.any',
    },
    'operationsTablet': <String>{
      'accounts.read', 'accounts.create', 'accounts.update', 'accounts.delete',
      'accounts.activate', 'accounts.assignRole',
      'sector.manage', 'location.manage', 'rule.manage',
      'tablet.manage', 'voice.delete.any',
    },
    'operationsBilling': <String>{
      'accounts.read', 'accounts.create', 'accounts.update', 'accounts.delete',
      'accounts.activate', 'accounts.assignRole',
      'sector.manage', 'location.manage', 'rule.manage',
      'bill.manage', 'voice.delete.any',
    },
    'operationsBillingTablet': <String>{
      'accounts.read', 'accounts.create', 'accounts.update', 'accounts.delete',
      'accounts.activate', 'accounts.assignRole',
      'sector.manage', 'location.manage', 'rule.manage',
      'bill.manage', 'tablet.manage', 'voice.delete.any',
    },
    'operationsBillingMonthly': <String>{
      'accounts.read', 'accounts.create', 'accounts.update', 'accounts.delete',
      'accounts.activate', 'accounts.assignRole',
      'sector.manage', 'location.manage', 'rule.manage',
      'bill.manage', 'monthly.manage', 'voice.delete.any',
    },
    'operationsAll': <String>{
      'accounts.read', 'accounts.create', 'accounts.update', 'accounts.delete',
      'accounts.activate', 'accounts.assignRole',
      'sector.manage', 'location.manage', 'rule.manage',
      'bill.manage', 'monthly.manage', 'tablet.manage',
      'voice.delete.any', 'single.operations.enter',
    },
    'generalAll': <String>{
      'accounts.read', 'accounts.create', 'accounts.update', 'accounts.delete',
      'accounts.activate', 'accounts.assignRole', 'accounts.limitManage',
      'sector.manage', 'location.manage', 'rule.manage',
      'bill.manage', 'monthly.manage', 'tablet.manage',
      'company.manage', 'voice.delete.any', 'single.operations.enter',
    },
  };

  static const Map<String, String> legacyBaseRoles = <String, String>{
    'dev': 'superAdmin',
    'adminBillMonthly': 'areaManager',
    'adminBillMonthlyTablet': 'areaManager',
    'adminBill': 'areaManager',
    'adminBillTablet': 'areaManager',
    'adminCommon': 'areaManager',
    'adminCommonTablet': 'areaManager',
    'userLocationMonthly': 'specialist',
    'userMonthly': 'specialist',
  };

  static const Map<String, String> legacyProfiles = <String, String>{
    'dev': 'generalAll',
    'adminBillMonthly': 'operationsBillingMonthly',
    'adminBillMonthlyTablet': 'operationsAll',
    'adminBill': 'operationsBilling',
    'adminBillTablet': 'operationsBillingTablet',
    'adminCommon': 'operationsCore',
    'adminCommonTablet': 'operationsTablet',
    'userLocationMonthly': 'monthlyLocation',
    'userMonthly': 'monthlyOnly',
  };

  static const Map<String, List<String>> permittedProfiles = <String, List<String>>{
    'fieldCommon': <String>['none'],
    'userCommon': <String>['none'],
    'specialist': <String>['monthlyOnly', 'monthlyLocation', 'billingOnly'],
    'areaManager': <String>[
      'operationsCore', 'operationsTablet', 'operationsBilling',
      'operationsBillingTablet', 'operationsBillingMonthly', 'operationsAll',
    ],
    'divisionManager': <String>['operationsAll'],
    'superAdmin': <String>['generalAll'],
  };

  static String baseRoleFor(String role) {
    if (baseRoles.contains(role)) return role;
    return legacyBaseRoles[role] ?? 'userCommon';
  }

  static String defaultProfileFor(String role) {
    final legacy = legacyProfiles[role];
    if (legacy != null) return legacy;
    switch (baseRoleFor(role)) {
      case 'specialist': return 'monthlyOnly';
      case 'areaManager': return 'operationsCore';
      case 'divisionManager': return 'operationsAll';
      case 'superAdmin': return 'generalAll';
      default: return 'none';
    }
  }

  static List<String> profilesForRole(String role) {
    if (legacyProfiles.containsKey(role)) return <String>[legacyProfiles[role]!];
    return permittedProfiles[baseRoleFor(role)] ?? const <String>['none'];
  }

  static String effectiveProfile(String role, String? requested) {
    final allowed = profilesForRole(role);
    if (requested != null && allowed.contains(requested)) return requested;
    return defaultProfileFor(role);
  }

  static String scopeForRole(String role) {
    switch (baseRoleFor(role)) {
      case 'fieldCommon':
      case 'userCommon': return 'self';
      case 'divisionManager': return 'division';
      case 'superAdmin': return 'global';
      default: return 'assignedAreas';
    }
  }

  static bool has(String role, String permission, {String? profileId}) {
    final profile = effectiveProfile(role, profileId);
    return (profilePermissions[profile] ?? const <String>{}).contains(permission);
  }

  static bool isKnownRole(String role) =>
      baseRoles.contains(role) || legacyBaseRoles.containsKey(role);

  static bool isHighPrivilege(String role) =>
      role == 'dev' || baseRoleFor(role) == 'superAdmin';

  static bool mayAssign(
    String actorRole,
    String requestedRole, {
    bool verifiedDeveloper = false,
  }) {
    if (!baseRoles.contains(requestedRole) || requestedRole == 'superAdmin') return false;
    if (verifiedDeveloper) return requestedRole != 'superAdmin';
    if (!isKnownRole(actorRole) || actorRole == 'dev') return false;
    final actor = baseRoleFor(actorRole);
    final target = baseRoleFor(requestedRole);
    if (target == 'superAdmin') return false;
    if (actor == 'superAdmin') return true;
    if (actor == 'divisionManager') {
      return const <String>{'fieldCommon', 'userCommon', 'specialist', 'areaManager'}
          .contains(target);
    }
    if (actor == 'areaManager') {
      return const <String>{'fieldCommon', 'userCommon', 'specialist'}
          .contains(target);
    }
    return false;
  }

  static bool mayAssignProfile(
    String actorRole,
    String actorProfileId,
    String targetRole,
    String targetProfileId, {
    bool verifiedDeveloper = false,
  }) {
    if (!mayAssign(actorRole, targetRole, verifiedDeveloper: verifiedDeveloper)) {
      return false;
    }
    if (!profilesForRole(targetRole).contains(targetProfileId)) return false;
    if (verifiedDeveloper) return true;
    final actorProfile = effectiveProfile(actorRole, actorProfileId);
    final actorPermissions = profilePermissions[actorProfile] ?? const <String>{};
    final requestedPermissions = profilePermissions[targetProfileId] ?? const <String>{};
    return actorPermissions.containsAll(requestedPermissions);
  }

  static bool mayManageTarget(
    String actorRole,
    String targetRole, {
    bool verifiedDeveloper = false,
  }) {
    if (verifiedDeveloper) return true;
    if (!isKnownRole(actorRole) || actorRole == 'dev') return false;
    if (!isKnownRole(targetRole) || targetRole == 'dev') return false;
    final actor = baseRoleFor(actorRole);
    final target = baseRoleFor(targetRole);
    if (actor == 'superAdmin') return true;
    if (target == 'superAdmin') return false;
    if (actor == 'divisionManager') return target != 'divisionManager';
    if (actor == 'areaManager') {
      return const <String>{'fieldCommon', 'userCommon', 'specialist'}
          .contains(target);
    }
    return false;
  }

  static bool mayOperateInScope({
    required String actorRole,
    required Iterable<String> actorDivisions,
    required Iterable<String> actorAreas,
    required String division,
    required String area,
    bool verifiedDeveloper = false,
  }) {
    if (verifiedDeveloper) return true;
    if (!isKnownRole(actorRole) || actorRole == 'dev') return false;
    switch (baseRoleFor(actorRole)) {
      case 'superAdmin':
        return true;
      case 'divisionManager':
        return division.isNotEmpty && actorDivisions.contains(division);
      case 'areaManager':
        return division.isNotEmpty && actorDivisions.contains(division) &&
            area.isNotEmpty && actorAreas.contains(area);
      default:
        return false;
    }
  }

  static String? validateAccountChange({
    required String actorRole,
    required String actorProfileId,
    required Iterable<String> actorDivisions,
    required Iterable<String> actorAreas,
    required bool actorIsTablet,
    required bool verifiedDeveloper,
    required String newRole,
    required String newProfileId,
    required String newScope,
    required String newDivision,
    required String newArea,
    String? oldRole,
    String? oldProfileId,
    String? oldScope,
    String? oldDivision,
    String? oldArea,
  }) {
    if (actorIsTablet) return 'TABLET_ROLE_ASSIGNMENT_DENIED';
    if (!isKnownRole(newRole)) return 'UNKNOWN_ROLE_DENIED';
    if (!profilesForRole(newRole).contains(newProfileId)) {
      return 'ROLE_PROFILE_INVALID';
    }
    if (newScope != scopeForRole(newRole)) return 'ROLE_SCOPE_INVALID';
    if (!mayOperateInScope(
      actorRole: actorRole,
      actorDivisions: actorDivisions,
      actorAreas: actorAreas,
      division: newDivision,
      area: newArea,
      verifiedDeveloper: verifiedDeveloper,
    )) {
      return 'MANAGEMENT_SCOPE_DENIED';
    }
    if (oldRole != null) {
      if (!mayManageTarget(actorRole, oldRole, verifiedDeveloper: verifiedDeveloper)) {
        return 'TARGET_ROLE_PROTECTED';
      }
      if (!mayOperateInScope(
        actorRole: actorRole,
        actorDivisions: actorDivisions,
        actorAreas: actorAreas,
        division: oldDivision ?? '',
        area: oldArea ?? '',
        verifiedDeveloper: verifiedDeveloper,
      )) {
        return 'PREVIOUS_MANAGEMENT_SCOPE_DENIED';
      }
      final previousProfile = effectiveProfile(oldRole, oldProfileId);
      final previousScope = oldScope == null || oldScope.isEmpty
          ? scopeForRole(oldRole)
          : oldScope;
      if (oldRole == newRole && previousProfile == newProfileId &&
          previousScope == newScope) {
        return null;
      }
    }
    if (!mayAssignProfile(
      actorRole,
      actorProfileId,
      newRole,
      newProfileId,
      verifiedDeveloper: verifiedDeveloper,
    )) {
      return 'ROLE_ASSIGNMENT_DENIED';
    }
    return null;
  }

  static Set<String> normalizedAssignments(Iterable<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();

  static String? validateAssignmentLists({
    required String actorRole,
    required Iterable<String> actorDivisions,
    required Iterable<String> actorAreas,
    required Iterable<String> newDivisions,
    required Iterable<String> newAreas,
    required Iterable<String> oldDivisions,
    required Iterable<String> oldAreas,
    required Map<String, Set<String>> resolvedAreaDivisions,
    bool verifiedDeveloper = false,
  }) {
    final nextDivisions = normalizedAssignments(newDivisions);
    final nextAreas = normalizedAssignments(newAreas);
    final previousDivisions = normalizedAssignments(oldDivisions);
    final previousAreas = normalizedAssignments(oldAreas);
    if (nextDivisions.isEmpty || nextAreas.isEmpty) {
      return 'ASSIGNMENT_LIST_EMPTY';
    }
    if (nextDivisions.length == previousDivisions.length &&
        nextAreas.length == previousAreas.length &&
        nextDivisions.containsAll(previousDivisions) &&
        nextAreas.containsAll(previousAreas)) {
      return null;
    }
    if (!verifiedDeveloper &&
        (!isKnownRole(actorRole) || actorRole == 'dev')) {
      return 'ASSIGNMENT_ACTOR_DENIED';
    }
    if (!verifiedDeveloper && baseRoleFor(actorRole) != 'superAdmin') {
      final allowedDivisions = normalizedAssignments(actorDivisions);
      final touchedDivisions = <String>{...nextDivisions, ...previousDivisions};
      if (!allowedDivisions.containsAll(touchedDivisions)) {
        return 'ASSIGNMENT_DIVISION_DENIED';
      }
      if (baseRoleFor(actorRole) != 'divisionManager' &&
          baseRoleFor(actorRole) != 'areaManager') {
        return 'ASSIGNMENT_SCOPE_DENIED';
      }
    }
    for (final area in nextAreas) {
      final related = resolvedAreaDivisions[area] ?? const <String>{};
      final selectedRelated = related.intersection(nextDivisions);
      if (selectedRelated.isEmpty) return 'ASSIGNMENT_AREA_RELATION_INVALID';
      if (selectedRelated.length > 1) {
        return 'ASSIGNMENT_AREA_NAME_AMBIGUOUS';
      }
      for (final division in selectedRelated) {
        if (!mayOperateInScope(
          actorRole: actorRole,
          actorDivisions: actorDivisions,
          actorAreas: actorAreas,
          division: division,
          area: area,
          verifiedDeveloper: verifiedDeveloper,
        )) {
          return 'ASSIGNMENT_AREA_DENIED';
        }
      }
    }
    final removedAreas = previousAreas.difference(nextAreas);
    if (!verifiedDeveloper && baseRoleFor(actorRole) == 'areaManager') {
      final allowedAreas = normalizedAssignments(actorAreas);
      if (!allowedAreas.containsAll(removedAreas)) {
        return 'PREVIOUS_ASSIGNMENT_AREA_DENIED';
      }
    }
    return null;
  }

  static String profileLabel(String profileId) =>
      profileLabels[profileId] ?? profileId;
}
