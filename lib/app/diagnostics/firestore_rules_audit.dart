import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_auth_rules_diagnostics.dart';

class FirestoreRulesWriteTarget {
  const FirestoreRulesWriteTarget({
    required this.operation,
    required this.collection,
    required this.pathTemplate,
    this.documentExists,
    this.changedKeys,
    this.fieldEvidence = 'UNKNOWN',
    this.documentEvidence = 'UNKNOWN',
  });

  final String operation;
  final String? collection;
  final String? pathTemplate;
  final bool? documentExists;
  final Set<String>? changedKeys;
  final String fieldEvidence;
  final String documentEvidence;
}

class FirestoreRulesAuditResult {
  const FirestoreRulesAuditResult({
    required this.expected,
    required this.observed,
    required this.comparison,
    required this.verification,
  });

  final String expected;
  final String observed;
  final String comparison;
  final String verification;

  String get detail => 'localRules=${FirestoreRulesAudit.localRulesVersion} '
      'expected=$expected observed=$observed comparison=$comparison '
      'verification=$verification';
}

class FirestoreRulesAudit {
  FirestoreRulesAudit._();

  static const String localRulesVersion = '38a6aa925d80c0ac';

  static const Set<String> _signedInRoots = <String>{
    'user_accounts',
    'user_account_codes',
    'tablet_accounts',
    'personal_accounts',
    'commute_user_logs',
    'plate_status',
    'parking_requests_view',
    'departure_requests_view',
    'parking_completed_view',
    'monthly_plate_status',
    'monthly_plate_status_view',
    'locations',
    'sector',
    'locationSlotReservations',
    'head_memo_libraries',
    'bill',
    'end_work_reports',
    'plate_out_log',
    'plate_counters',
    'plate_billing_counts',
    'commute_true_false',
    'voice_channels',
    'rule',
  };

  static bool _isRead(String operation) =>
      <String>{'GET', 'QUERY', 'LISTEN_START', 'AGGREGATION'}
          .contains(operation);

  static bool _isWrite(String operation) =>
      <String>{'SET', 'CREATE', 'UPDATE', 'DELETE'}.contains(operation);

  static String? pathTemplateFor(String? path) {
    if (path == null || path.isEmpty) return null;
    final parts = path.split('/');
    if (parts.any((part) => part.isEmpty)) return null;
    return List<String>.generate(parts.length, (index) =>
        index.isEven ? parts[index] : '*').join('/');
  }

  static String? collectionFor(String? path) {
    final template = pathTemplateFor(path);
    return template?.split('/').first;
  }

  static Set<String>? updateKeys(Object? data, {bool merge = true}) {
    if (!merge || data is! Map) return null;
    final keys = <String>{};
    for (final key in data.keys) {
      if (key is! String || key.isEmpty) return null;
      keys.add(key.split('.').first);
    }
    return keys;
  }

  static Set<String>? safeProjectionKeys(Object? data) {
    final keys = updateKeys(data);
    if (keys == null) return null;
    if (!keys.every(<String>{'users', 'updatedAt'}.contains)) {
      return null;
    }
    return keys;
  }

  static bool _hasTransform(Object? value) {
    if (value is Map) {
      return value.values.any(_hasTransform);
    }
    if (value is Iterable) {
      return value.any(_hasTransform);
    }
    return value is FieldValue;
  }

  static bool _equivalent(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key) || !_equivalent(entry.value, b[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equivalent(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static Map<String, dynamic>? _plainMap(Object? value) {
    if (value is! Map) return null;
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) return null;
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static Map<String, dynamic>? _mergeMaps(
    Map<String, dynamic> existing,
    Map<String, dynamic> patch,
  ) {
    final result = <String, dynamic>{...existing};
    for (final entry in patch.entries) {
      if (entry.key.contains('.')) return null;
      final oldNested = _plainMap(result[entry.key]);
      final nextNested = _plainMap(entry.value);
      if (nextNested != null && oldNested != null) {
        final merged = _mergeMaps(oldNested, nextNested);
        if (merged == null) return null;
        result[entry.key] = merged;
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  static Set<String>? affectedKeysFromKnownState({
    required Object? before,
    required Object? payload,
    required bool merge,
    bool mergeNestedMaps = false,
  }) {
    final previous = _plainMap(before);
    final patch = _plainMap(payload);
    if (previous == null || patch == null || _hasTransform(patch)) {
      return null;
    }
    Map<String, dynamic>? next;
    if (!merge) {
      next = patch;
    } else if (mergeNestedMaps) {
      next = _mergeMaps(previous, patch);
    } else {
      if (patch.keys.any((key) => key.contains('.'))) return null;
      next = <String, dynamic>{...previous, ...patch};
    }
    if (next == null) return null;
    final keys = <String>{...previous.keys, ...next.keys};
    return keys.where((key) =>
        previous.containsKey(key) != next!.containsKey(key) ||
        !_equivalent(previous[key], next[key])).toSet();
  }

  static String expected({
    required String? collection,
    required String operation,
    String? pathTemplate,
    Set<String>? changedKeys,
    bool? documentExists,
    FirebaseAuthRulesSnapshot? authOverride,
    bool requireCapturedAuth = false,
  }) {
    final session = requireCapturedAuth
        ? authOverride
        : authOverride ?? FirebaseAuthRulesDiagnostics.current;
    if (session == null || !session.complete) return 'UNKNOWN';
    if (session.sessionUid == null) return 'DENY';
    if (session.provider == 'unknown') return 'UNKNOWN';
    if (session.provider != 'google.com') return 'DENY';
    if (session.emailVerified == null) return 'UNKNOWN';
    if (session.emailVerified != true) return 'DENY';
    if (!_isRead(operation) && !_isWrite(operation)) return 'UNKNOWN';

    final parts = pathTemplate?.split('/');
    final validPath = parts != null && parts.isNotEmpty &&
        parts.every((part) => part.isNotEmpty) &&
        List<int>.generate(parts.length, (i) => i)
            .every((i) => i.isEven || parts[i] == '*');
    final root = validPath ? parts.first : collection;
    if (root == null || root.isEmpty) return 'UNKNOWN';
    if (pathTemplate != null && !validPath) return 'UNKNOWN';
    if (_isWrite(operation) &&
        (!validPath || parts.length.isOdd)) return 'UNKNOWN';

    if (validPath && parts.length >= 4 && parts.length.isEven &&
        parts[parts.length - 2] == 'plates' && _isRead(operation)) {
      return 'ALLOW';
    }
    if (_signedInRoots.contains(root) || root == 'plates') {
      return 'ALLOW';
    }
    if (root == 'areas' || root == 'divisions') {
      if (_isRead(operation)) return 'ALLOW';
      if (session.developerEmailMatch == null) return 'UNKNOWN';
      return session.developerEligible ? 'ALLOW' : 'DENY';
    }
    if (root == 'user_accounts_show') {
      if (!validPath) return 'UNKNOWN';
      if (parts.length == 4 && parts[2] == 'users') return 'ALLOW';
      if (parts.length == 3 && parts[2] == 'users' && _isRead(operation)) {
        return 'ALLOW';
      }
      if (parts.length != 2 &&
          !(parts.length == 1 && _isRead(operation))) {
        return 'DENY';
      }
      if (_isRead(operation)) return 'ALLOW';
      if (session.developerEmailMatch == null) return 'UNKNOWN';
      if (session.developerEligible) return 'ALLOW';
      if (operation == 'DELETE') return 'DENY';
      if (operation == 'CREATE' ||
          (operation == 'SET' && documentExists == false)) {
        if (changedKeys == null) return 'UNKNOWN';
        if (!changedKeys.contains('users') ||
            !changedKeys.contains('updatedAt') ||
            !changedKeys.every(<String>{'users', 'updatedAt'}.contains)) {
          return 'DENY';
        }
        return 'UNKNOWN';
      }
      if (operation == 'UPDATE' && documentExists == false) return 'DENY';
      if (operation == 'SET' && documentExists != true) return 'UNKNOWN';
      if (operation == 'UPDATE' || operation == 'SET') {
        if (changedKeys == null) return 'UNKNOWN';
        return changedKeys.every(
          <String>{'users', 'updatedAt'}.contains,
        ) ? 'ALLOW' : 'DENY';
      }
      return 'UNKNOWN';
    }
    if (!validPath) return 'UNKNOWN';
    return 'DENY';
  }

  static String expectedWrites(
    Iterable<FirestoreRulesWriteTarget> targets, {
    FirebaseAuthRulesSnapshot? authOverride,
    bool requireCapturedAuth = true,
  }) {
    var foundAny = false;
    var unknown = false;
    for (final target in targets) {
      foundAny = true;
      if (target.documentEvidence == 'PREEXISTING_SNAPSHOT' &&
          target.collection == 'user_accounts_show' &&
          target.operation == 'SET') {
        unknown = true;
        continue;
      }
      final value = expected(
        collection: target.collection,
        operation: target.operation,
        pathTemplate: target.pathTemplate,
        changedKeys: target.changedKeys,
        documentExists: target.documentExists,
        authOverride: authOverride,
        requireCapturedAuth: requireCapturedAuth,
      );
      if (value == 'DENY') return 'DENY';
      if (value != 'ALLOW') unknown = true;
    }
    if (!foundAny || unknown) return 'UNKNOWN';
    return 'ALLOW';
  }

  static String expectedTransaction({
    required Iterable<FirestoreRulesWriteTarget> reads,
    required Iterable<FirestoreRulesWriteTarget> writes,
    FirebaseAuthRulesSnapshot? authOverride,
  }) {
    return expectedWrites(
      <FirestoreRulesWriteTarget>[...reads, ...writes],
      authOverride: authOverride,
      requireCapturedAuth: true,
    );
  }

  static FirestoreRulesAuditResult compare({
    required String? collection,
    required String operation,
    required bool success,
    required String? firebaseCode,
    required bool? fromCache,
    String? pathTemplate,
    Set<String>? changedKeys,
    bool? documentExists,
    FirebaseAuthRulesSnapshot? authOverride,
    bool requireCapturedAuth = false,
    bool sessionChanged = false,
    String? authEvidence,
    bool requestSent = true,
    String? expectedOverride,
  }) {
    final policy = authEvidence != null || sessionChanged
        ? 'UNKNOWN'
        : expectedOverride ?? expected(
            collection: collection,
            operation: operation,
            pathTemplate: pathTemplate,
            changedKeys: changedKeys,
            documentExists: documentExists,
            authOverride: authOverride,
            requireCapturedAuth: requireCapturedAuth,
          );
    final observed = success
        ? (fromCache == true ? 'UNKNOWN' : 'ALLOW')
        : firebaseCode == 'permission-denied' && requestSent
            ? 'DENY'
            : 'UNKNOWN';
    final verification = !requestSent
        ? 'NOT_SENT'
        : authEvidence != null
            ? authEvidence
            : sessionChanged
                ? 'AUTH_CHANGED'
                : success
                ? fromCache == true
                    ? 'CACHE_ONLY'
                    : _isRead(operation) && fromCache == null &&
                            operation != 'AGGREGATION'
                        ? 'SOURCE_UNCONFIRMED'
                        : 'SDK_OBSERVED'
                : firebaseCode == 'permission-denied'
                    ? 'SDK_PERMISSION_DENIED'
                    : 'NO_POLICY_EVIDENCE';
    final comparable = verification == 'SDK_OBSERVED' ||
        verification == 'SDK_PERMISSION_DENIED';
    final comparison = !comparable || policy == 'UNKNOWN' ||
            observed == 'UNKNOWN'
        ? 'NOT_VERIFIED'
        : policy == observed
            ? 'CONSISTENT'
            : observed == 'ALLOW'
                ? 'UNEXPECTED_ALLOW'
                : 'UNEXPECTED_DENY';
    return FirestoreRulesAuditResult(
      expected: policy,
      observed: observed,
      comparison: comparison,
      verification: verification,
    );
  }
}
