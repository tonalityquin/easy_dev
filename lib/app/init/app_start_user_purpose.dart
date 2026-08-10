enum AppStartUserPurpose {
  branchEmployee,
  headOfficeEmployee,
  tabletInstallation,
  commuteRecorder,
  personal,
}

extension AppStartUserPurposeValues on AppStartUserPurpose {
  String get storageValue {
    return switch (this) {
      AppStartUserPurpose.branchEmployee => 'branch_employee',
      AppStartUserPurpose.headOfficeEmployee => 'head_office_employee',
      AppStartUserPurpose.tabletInstallation => 'tablet_installation',
      AppStartUserPurpose.commuteRecorder => 'commute_recorder',
      AppStartUserPurpose.personal => 'personal',
    };
  }

  String get label {
    return switch (this) {
      AppStartUserPurpose.branchEmployee => '지사 직원',
      AppStartUserPurpose.headOfficeEmployee => '본사 직원',
      AppStartUserPurpose.tabletInstallation => '태블릿 설치형',
      AppStartUserPurpose.commuteRecorder => '출퇴근 기록형',
      AppStartUserPurpose.personal => '개인용',
    };
  }

  String get description {
    return switch (this) {
      AppStartUserPurpose.branchEmployee => '현장 업무와 주차 관리',
      AppStartUserPurpose.headOfficeEmployee => '본사 업무 기능 사용',
      AppStartUserPurpose.tabletInstallation => '현장 고정 태블릿 설치',
      AppStartUserPurpose.commuteRecorder => '출퇴근 기록 중심 사용',
      AppStartUserPurpose.personal => '개인 기능 중심 사용',
    };
  }

  List<int> get permissionStepNumbers {
    return switch (this) {
      AppStartUserPurpose.branchEmployee => const <int>[1, 2, 3, 4, 5, 6, 7],
      AppStartUserPurpose.headOfficeEmployee =>
        const <int>[1, 2, 3, 4, 5, 6, 7],
      AppStartUserPurpose.tabletInstallation => const <int>[1, 2, 4, 6],
      AppStartUserPurpose.commuteRecorder => const <int>[1, 2, 3, 4, 6],
      AppStartUserPurpose.personal => const <int>[1, 2],
    };
  }

  bool get skipsPolicyAndPostSetup {
    return switch (this) {
      AppStartUserPurpose.tabletInstallation => true,
      AppStartUserPurpose.personal => true,
      AppStartUserPurpose.branchEmployee => false,
      AppStartUserPurpose.headOfficeEmployee => false,
      AppStartUserPurpose.commuteRecorder => false,
    };
  }

  bool get requiresGoogleServicesSetup => !skipsPolicyAndPostSetup;
}

AppStartUserPurpose? parseAppStartUserPurpose(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  for (final purpose in AppStartUserPurpose.values) {
    if (purpose.storageValue == value) return purpose;
  }
  return null;
}
