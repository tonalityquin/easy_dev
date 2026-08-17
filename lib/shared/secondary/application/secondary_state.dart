import 'package:flutter/material.dart';

import '../../../app/models/capability.dart';
import '../../../features/selector/application/dev_auth.dart';
import 'secondary_info.dart';

class SecondaryState with ChangeNotifier {
  bool _isLoading = false;
  RoleType _role = RoleType.userCommon;
  CapSet _areaCaps = const <Capability>{};
  bool _devLoggedIn = false;
  bool _hasLoadedDevLogin = false;
  bool _devRefreshScheduled = false;
  int _devRefreshToken = 0;

  bool get isLoading => _isLoading;
  bool get devLoggedIn => _devLoggedIn;
  RoleType get role => _role;
  CapSet get areaCaps => Set<Capability>.unmodifiable(_areaCaps);

  bool roleAllows(Section section) {
    return (kRolePolicy[_role] ?? const <Section>{}).contains(section);
  }

  CapSet requiredCapabilities(Section section) {
    return Set<Capability>.unmodifiable(
      kSectionRequires[section] ?? const <Capability>{},
    );
  }

  bool capabilityAllows(Section section) {
    return Cap.supports(_areaCaps, requiredCapabilities(section));
  }

  bool canAccess(Section section) {
    if (!roleAllows(section)) return false;
    if (section == Section.backend && !_devLoggedIn) return false;
    return capabilityAllows(section);
  }

  String disabledReason(Section section) {
    if (!roleAllows(section)) {
      return '현재 계정 권한으로 ${_sectionLabel(section)}을 사용할 수 없습니다.';
    }
    if (section == Section.backend && !_devLoggedIn) {
      return '백엔드 컨트롤러를 사용하려면 개발자 로그인이 필요합니다.';
    }
    if (!capabilityAllows(section)) {
      final required = requiredCapabilities(section);
      final labels = required.map((capability) => capability.label).join(' · ');
      if (labels.isEmpty) {
        return '현재 지점에서는 ${_sectionLabel(section)}을 사용할 수 없습니다.';
      }
      return '현재 지점에 $labels 기능이 활성화되어 있지 않습니다.';
    }
    return '';
  }

  String accessDebugReason(Section section) {
    if (!roleAllows(section)) {
      return 'role_denied role=${_role.name} section=${section.name}';
    }
    if (section == Section.backend && !_devLoggedIn) {
      return 'developer_login_required section=${section.name}';
    }
    if (!capabilityAllows(section)) {
      final required = requiredCapabilities(section);
      final missing = required
          .where((capability) => !_areaCaps.contains(capability))
          .map((capability) => capability.name)
          .join(',');
      return 'capability_denied section=${section.name} missing=$missing areaCaps=${_areaCaps.map((capability) => capability.name).join(',')}';
    }
    return 'allowed section=${section.name}';
  }

  void updateAccess({
    required RoleType role,
    required CapSet areaCaps,
  }) {
    final roleChanged = _role != role;
    final capsChanged = !_sameCaps(_areaCaps, areaCaps);

    if (roleChanged) {
      _role = role;
    }
    if (capsChanged) {
      _areaCaps = Set<Capability>.from(areaCaps);
    }

    if (roleChanged || capsChanged) {
      debugPrint(
        '[SecondaryState] access_updated role=${_role.name} caps=${_areaCaps.map((capability) => capability.name).join(',')}',
      );
      notifyListeners();
    }

    if (!_hasLoadedDevLogin) {
      _scheduleDeveloperLoginRefresh();
    }
  }

  void _scheduleDeveloperLoginRefresh() {
    if (_devRefreshScheduled || _isLoading) return;

    _devRefreshScheduled = true;
    Future<void>.microtask(() async {
      _devRefreshScheduled = false;
      await refreshDeveloperLogin();
    });
  }

  Future<void> refreshDeveloperLogin() async {
    final token = ++_devRefreshToken;
    if (!_isLoading) {
      _isLoading = true;
      notifyListeners();
    }

    final loggedIn = await DevAuth.isDeveloperLoggedIn();
    if (token != _devRefreshToken) return;

    _hasLoadedDevLogin = true;
    final changed = _devLoggedIn != loggedIn;
    _devLoggedIn = loggedIn;
    _isLoading = false;

    debugPrint(
      '[SecondaryState] developer_login refreshed=$_devLoggedIn changed=$changed',
    );
    notifyListeners();
  }

  String _sectionLabel(Section section) {
    switch (section) {
      case Section.local:
        return '설정';
      case Section.user:
        return '계정 관리';
      case Section.sector:
        return '섹터 관리';
      case Section.location:
        return '구역 관리';
      case Section.tablet:
        return '태블릿 관리';
      case Section.monthly:
        return '정기 주차 관리';
      case Section.bill:
        return '정산 관리';
      case Section.backend:
        return '백엔드 컨트롤러';
      case Section.area:
        return '지역 추가';
    }
  }

  bool _sameCaps(CapSet a, CapSet b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final capability in a) {
      if (!b.contains(capability)) return false;
    }
    return true;
  }
}
