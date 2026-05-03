import 'package:flutter/material.dart';

import '../../../app/models/capability.dart';
import '../../../features/selector/application/dev_auth.dart';
import 'secondary_info.dart';

class SecondaryState with ChangeNotifier {
  int _selectedIndex = 0;
  List<SecondaryInfo> _pages;
  bool _isLoading = false;
  RoleType _role = RoleType.userCommon;
  CapSet _areaCaps = const <Capability>{};
  bool _devLoggedIn = false;
  bool _hasLoadedDevLogin = false;
  bool _devRefreshScheduled = false;
  int _devRefreshToken = 0;

  SecondaryState({List<SecondaryInfo> pages = const [tabLocalData]})
      : _pages = pages;

  int get selectedIndex => _selectedIndex;

  List<SecondaryInfo> get pages => _pages;

  bool get isLoading => _isLoading;

  bool get devLoggedIn => _devLoggedIn;

  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      debugPrint('⚠️ 잘못된 인덱스 접근: $index');
      return;
    }
    if (_selectedIndex != index) {
      _selectedIndex = index;
      notifyListeners();
    }
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

    final newPages = _computePages();
    final pagesChanged = !_sameByTitle(_pages, newPages);

    if (pagesChanged) {
      _setPages(newPages, keepIndex: true, notify: false);
    }

    if (roleChanged || capsChanged || pagesChanged) {
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
    _devLoggedIn = loggedIn;

    final newPages = _computePages();
    final pagesChanged = !_sameByTitle(_pages, newPages);

    _isLoading = false;

    if (pagesChanged) {
      _setPages(newPages, keepIndex: true, notify: false);
    }

    notifyListeners();
  }

  void updatePages(List<SecondaryInfo> newPages, {bool keepIndex = false}) {
    _setPages(newPages, keepIndex: keepIndex, notify: true);
  }

  List<SecondaryInfo> _computePages() {
    final fallbackPages =
        _devLoggedIn ? const [tabLocalData, tabBackend] : const [tabLocalData];
    final allowedSections = kRolePolicy[_role] ?? const <Section>{};

    if (allowedSections.isEmpty) return fallbackPages;

    final pages = <SecondaryInfo>[];
    for (final section in allowedSections) {
      if (section == Section.backend && !_devLoggedIn) continue;

      final need = kSectionRequires[section] ?? const <Capability>{};
      if (Cap.supports(_areaCaps, need)) {
        final info = kSectionTab[section];
        if (info != null) pages.add(info);
      }
    }

    return pages.isEmpty ? fallbackPages : pages;
  }

  void _setPages(
    List<SecondaryInfo> newPages, {
    required bool keepIndex,
    required bool notify,
  }) {
    _pages = newPages;
    if (!keepIndex || _selectedIndex >= newPages.length) {
      _selectedIndex = 0;
    }
    if (notify) notifyListeners();
  }

  bool _sameByTitle(List<SecondaryInfo> a, List<SecondaryInfo> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].title != b[i].title) return false;
    }
    return true;
  }

  bool _sameCaps(CapSet a, CapSet b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final cap in a) {
      if (!b.contains(cap)) return false;
    }
    return true;
  }
}
