import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/account_permission_policy.dart';

class CompanyGradePolicy {
  const CompanyGradePolicy({
    required this.companyId,
    required this.gradeId,
    required this.name,
    required this.permissionKeys,
    required this.version,
    required this.enabled,
  });

  final String companyId;
  final String gradeId;
  final String name;
  final Set<String> permissionKeys;
  final int version;
  final bool enabled;

  bool matches(Iterable<String> permissions) {
    final values = permissions.toList(growable: false);
    final supplied = values.toSet();
    return values.length == supplied.length &&
        supplied.length == permissionKeys.length &&
        supplied.containsAll(permissionKeys);
  }
}

class CompanyGradePolicyService {
  CompanyGradePolicyService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const Set<String> reservedGradeIds = <String>{
    'headquartersAdmin',
    'headquartersStaff',
    'branchAdminPlus',
    'branchAdmin',
    'branchWorker',
  };

  static bool validGradeId(String gradeId) {
    final value = gradeId.trim();
    return gradeId == value &&
        value.isNotEmpty &&
        value.length <= 64 &&
        !reservedGradeIds.contains(value) &&
        RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value);
  }

  static CompanyGradePolicy parse({
    required String companyId,
    required String gradeId,
    required Map<String, dynamic>? data,
  }) {
    if (!validGradeId(gradeId) || data == null ||
        data['companyId'] != companyId || data['gradeId'] != gradeId ||
        data['enabled'] is! bool || data['version'] is! int ||
        (data['version'] as int) < 1 || data['permissionKeys'] is! List) {
      throw StateError('ACCOUNT_GRADE_POLICY_INVALID:$companyId/$gradeId');
    }
    final raw = data['permissionKeys'] as List;
    if (raw.any((value) => value is! String ||
        value.trim() != value || value.isEmpty)) {
      throw StateError('ACCOUNT_GRADE_PERMISSION_INVALID:$companyId/$gradeId');
    }
    final keys = raw.cast<String>().toSet();
    if (keys.length != raw.length ||
        !AccountPermissionPolicy.generalPermissionKeys.containsAll(keys)) {
      throw StateError('ACCOUNT_GRADE_PERMISSION_INVALID:$companyId/$gradeId');
    }
    final label = (data['name'] ?? '').toString().trim();
    return CompanyGradePolicy(
      companyId: companyId,
      gradeId: gradeId,
      name: label.isEmpty ? AccountPermissionPolicy.gradeLabel(gradeId) : label,
      permissionKeys: Set<String>.unmodifiable(keys),
      version: data['version'] as int,
      enabled: data['enabled'] as bool,
    );
  }

  DocumentReference<Map<String, dynamic>> reference(String companyId, String gradeId) =>
      _firestore.collection('company_grade_policies').doc(companyId)
          .collection('grades').doc(gradeId);

  Future<CompanyGradePolicy> load(String companyId, String gradeId) async {
    final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => reference(companyId, gradeId)
        .get(const GetOptions(source: Source.server)), source: 'company_grade_policy_service.get');
    final policy = parse(
      companyId: companyId,
      gradeId: gradeId,
      data: snapshot.data(),
    );
    if (!policy.enabled) {
      throw StateError('ACCOUNT_GRADE_POLICY_DISABLED:$companyId/$gradeId');
    }
    return policy;
  }

  Future<Map<String, CompanyGradePolicy>> loadAll(String companyId) async {
    final snapshots = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore.collection('company_grade_policies')
        .doc(companyId).collection('grades')
        .get(const GetOptions(source: Source.server)), source: 'company_grade_policy_service.get');
    final policies = <String, CompanyGradePolicy>{};
    for (final document in snapshots.docs) {
      if (reservedGradeIds.contains(document.id)) continue;
      final policy = parse(
        companyId: companyId,
        gradeId: document.id,
        data: document.data(),
      );
      policies[document.id] = policy;
    }
    return policies;
  }

  Future<CompanyGradePolicy> loadInTransaction(
    Transaction transaction,
    String companyId,
    String gradeId,
  ) async {
    final document = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(reference(companyId, gradeId)), source: 'company_grade_policy_service.get');
    final policy = parse(
      companyId: companyId,
      gradeId: gradeId,
      data: document.data(),
    );
    if (!policy.enabled) {
      throw StateError('ACCOUNT_GRADE_POLICY_DISABLED:$companyId/$gradeId');
    }
    return policy;
  }

  static void assertMatches(CompanyGradePolicy policy, Iterable<String> keys) {
    if (!policy.matches(keys)) {
      throw StateError('ACCOUNT_GRADE_PERMISSION_MISMATCH:${policy.gradeId}');
    }
  }
}
