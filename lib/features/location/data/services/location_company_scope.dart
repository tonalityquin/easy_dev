import '../../../../shared/area_remote_settings/application/area_snapshot_scope.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../dev/application/developer_account_authorization.dart';

class LocationCompanyScope {
  LocationCompanyScope._();

  static Future<String?> resolve(FirebaseFirestore firestore) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim().toLowerCase() ?? '';
    if (user == null || email.isEmpty) {
      throw StateError('LOCATION_GOOGLE_ACCOUNT_REQUIRED');
    }
    if (DeveloperAccountAuthorization.allowedEmails.contains(email)) {
      final company = AreaSnapshotScope.division.trim();
      if (company.isEmpty) throw StateError('LOCATION_DEVELOPER_COMPANY_SELECTION_REQUIRED');
      StatusDialog.recordDebugOperation('location.scope', 'developer_scope', details: {'companyId': company});
      StatusDialog.recordDebugOperation('location.scope', 'identity_scope', details: {'companyId': company});
    return company;
    }
    final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => firestore.collection('login_identity_accounts')
        .doc(email).get(const GetOptions(source: Source.server)), source: 'location_company_scope.get');
    final data = snapshot.data();
    final company = (data?['companyId'] ?? '').toString().trim();
    if (company.isEmpty || data?['enabled'] != true) {
      throw StateError('LOCATION_COMPANY_IDENTITY_REQUIRED');
    }
    return company;
  }
}
