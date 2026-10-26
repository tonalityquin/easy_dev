class AccountPermissionPolicy {
  const AccountPermissionPolicy._();

  static const Set<String> keys = <String>{
    'accounts.read',
    'accounts.create',
    'accounts.update',
    'accounts.delete',
    'accounts.activate',
    'accounts.grantPermissions',
    'sector.manage',
    'location.manage',
    'rule.manage',
    'tablet.manage',
    'bill.manage',
    'monthly.manage',
    'company.manage',
    'voice.delete.any',
    'single.operations.enter',
  };


  static const Map<String, Set<String>> presets = <String, Set<String>>{
    'headquartersAdmin': keys,
    'branchAdminPlus': <String>{
      'accounts.read',
      'accounts.create',
      'accounts.update',
      'accounts.delete',
      'accounts.grantPermissions',
      'location.manage',
      'bill.manage',
      'monthly.manage',
      'single.operations.enter',
    },
    'branchAdmin': <String>{
      'monthly.manage',
      'single.operations.enter',
    },
    'branchWorker': <String>{
      'single.operations.enter',
    },
  };

  static const Map<String, String> presetLabels = <String, String>{
    'headquartersAdmin': '본사 관리자',
    'branchAdminPlus': '지사 관리자++',
    'branchAdmin': '지사 관리자',
    'branchWorker': '지사 근무자',
  };

  static const Map<String, String> permissionLabels = <String, String>{
    'accounts.read': '계정 조회',
    'accounts.create': '계정 생성',
    'accounts.update': '계정 수정',
    'accounts.delete': '계정 삭제',
    'accounts.activate': '계정 활성화·비활성화',
    'accounts.grantPermissions': '계정 권한 부여',
    'sector.manage': '구역 관리',
    'location.manage': '지역 관리',
    'rule.manage': '운영 규칙 관리',
    'tablet.manage': '태블릿 관리',
    'bill.manage': '요금 관리',
    'monthly.manage': '월정기 관리',
    'company.manage': '회사 관리',
    'voice.delete.any': '다른 사용자의 음성 기록 삭제',
    'single.operations.enter': '싱글 업무 기능 진입',
  };

  static const Map<String, String> modeLabels = <String, String>{
    'single': '싱글 모드',
    'double': '더블 모드',
    'triple': '트리플 모드',
    'minor': '마이너 모드',
  };

  static String permissionLabel(String key) => permissionLabels[key] ?? key;

  static String modeLabel(String mode) => modeLabels[mode] ?? mode;

  static Set<String> presetPermissions(String id) =>
      Set<String>.of(presets[id] ?? const <String>{});

  static String? presetIdFor(Iterable<String> values) {
    final current = values.map((item) => item.trim()).toSet();
    for (final entry in presets.entries) {
      if (entry.value.length == current.length &&
          current.containsAll(entry.value)) {
        return entry.key;
      }
    }
    return null;
  }

  static String presetLabelFor(Iterable<String> values) =>
      presetLabels[presetIdFor(values)] ?? '기존 권한 구성';

  static Set<String> sanitize(Iterable<String> values) => values
      .map((item) => item.trim())
      .where(keys.contains)
      .toSet();

  static bool has(Iterable<String> values, String key) =>
      keys.contains(key) && values.contains(key);

  static bool mayGrant(Iterable<String> actor, Iterable<String> requested) {
    final permitted = sanitize(actor);
    final original = requested.map((key) => key.trim()).toSet();
    if (!keys.containsAll(original)) return false;
    return permitted.contains('accounts.grantPermissions') &&
        permitted.containsAll(original);
  }
  static Set<String> normalizedAssignments(Iterable<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();

  static String? validateAssignments({
    required Iterable<String> actorPermissions,
    required Iterable<String> actorDivisions,
    required Iterable<String> actorAreas,
    required Iterable<String> newDivisions,
    required Iterable<String> newAreas,
  }) {
    final permissions = sanitize(actorPermissions);
    if (!permissions.contains('accounts.update') &&
        !permissions.contains('accounts.create')) {
      return 'ACCOUNT_ASSIGNMENT_PERMISSION_DENIED';
    }
    final divisions = normalizedAssignments(newDivisions);
    final areas = normalizedAssignments(newAreas);
    if (divisions.isEmpty || areas.isEmpty) return 'ACCOUNT_ASSIGNMENT_REQUIRED';
    if (!normalizedAssignments(actorDivisions).containsAll(divisions) ||
        !normalizedAssignments(actorAreas).containsAll(areas)) {
      return 'ACCOUNT_ASSIGNMENT_SCOPE_DENIED';
    }
    return null;
  }

  static String? validateChange({
    required Iterable<String> actorPermissions,
    required Iterable<String> previousPermissions,
    required Iterable<String> nextPermissions,
    required bool isCreating,
    required bool changesPermissions,
  }) {
    final actor = sanitize(actorPermissions);
    if (!actor.contains(isCreating ? 'accounts.create' : 'accounts.update')) {
      return 'ACCOUNT_WRITE_PERMISSION_DENIED';
    }
    final old = sanitize(previousPermissions);
    final next = sanitize(nextPermissions);
    if ((isCreating || changesPermissions || old.length != next.length ||
            !old.containsAll(next)) &&
        presetIdFor(nextPermissions) == null) {
      return 'ACCOUNT_PERMISSION_PRESET_REQUIRED';
    }
    if (changesPermissions || old.length != next.length || !old.containsAll(next)) {
      if (!mayGrant(actor, next)) return 'ACCOUNT_PERMISSION_GRANT_DENIED';
    }
    return null;
  }
}
