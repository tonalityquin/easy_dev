import 'company_grade_policy_service.dart';

class CompanyGradePolicySelectionCache {
  CompanyGradePolicySelectionCache._();

  static final CompanyGradePolicySelectionCache instance =
      CompanyGradePolicySelectionCache._();

  static const Duration maxAge = Duration(minutes: 5);
  final Map<String, _GradePolicyCacheEntry> _entries =
      <String, _GradePolicyCacheEntry>{};

  Future<Map<String, CompanyGradePolicy>> load(
    String companyId, {
    bool forceRefresh = false,
    void Function(String event)? onEvent,
  }) {
    final company = companyId.trim();
    if (company.isEmpty) {
      return Future<Map<String, CompanyGradePolicy>>.error(
        StateError('COMPANY_ID_REQUIRED'),
      );
    }
    final existing = _entries[company];
    if (!forceRefresh && existing != null &&
        DateTime.now().difference(existing.createdAt) < maxAge) {
      onEvent?.call('cache_hit');
      return existing.future;
    }
    final future = CompanyGradePolicyService().loadAll(company);
    final entry = _GradePolicyCacheEntry(
      future: future,
      createdAt: DateTime.now(),
    );
    _entries[company] = entry;
    onEvent?.call(forceRefresh ? 'forced_refresh' : 'server_request');
    future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_entries[company], entry)) {
          _entries.remove(company);
        }
      },
    );
    return future;
  }

  void invalidate(String companyId) {
    _entries.remove(companyId.trim());
  }

  void clear() {
    _entries.clear();
  }
}

class _GradePolicyCacheEntry {
  const _GradePolicyCacheEntry({
    required this.future,
    required this.createdAt,
  });

  final Future<Map<String, CompanyGradePolicy>> future;
  final DateTime createdAt;
}
