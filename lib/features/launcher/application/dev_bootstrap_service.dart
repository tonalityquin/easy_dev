import '../../../app/diagnostics/firebase_activity_meter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../app/auth/google_auth_session.dart';
import '../../../app/models/capability.dart';
import '../../../app/terminal/application/parkinworkin_terminal_diagnostics.dart';
import '../../../app/models/account_role_diagnostics.dart';
import '../../../app/utils/secure_auth_diagnostics.dart';
import '../../../shared/auth/account_code_number.dart';
import '../../../shared/secondary/data/services/dev_user_write_service.dart';
import '../../../shared/secondary/pages/sheets/tabs/dev_management_common.dart';
import '../../account/domain/models/user/user_model.dart';
import '../../account/domain/models/user/user_account_view_projection.dart';
import '../../account/data/services/user_account_show_map.dart';
import '../../dashboard/applications/common/firebase_google_auth_bridge.dart';
import '../../dev/application/developer_account_authorization.dart';

class DevBootstrapException implements Exception {
  const DevBootstrapException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DevBootstrapResult {
  const DevBootstrapResult({
    required this.codeNumber,
    required this.divisionCreated,
    required this.areaCreated,
    required this.metaCreated,
    required this.accountCreated,
    required this.reservationRepaired,
    required this.projectionRepaired,
  });

  final String codeNumber;
  final bool divisionCreated;
  final bool areaCreated;
  final bool metaCreated;
  final bool accountCreated;
  final bool reservationRepaired;
  final bool projectionRepaired;

  int get writeOperations =>
      (divisionCreated ? 1 : 0) +
      (areaCreated ? 1 : 0) +
      (metaCreated ? 1 : 0) +
      (accountCreated ? 3 : 0) +
      (reservationRepaired ? 1 : 0) +
      (projectionRepaired ? 1 : 0);

  bool get unchanged => writeOperations == 0;
}

class _DevScaffold {
  const _DevScaffold({
    required this.accountId,
    required this.divisionCreated,
    required this.areaCreated,
    required this.metaCreated,
  });

  final String accountId;
  final bool divisionCreated;
  final bool areaCreated;
  final bool metaCreated;
}

class _DevAccountRepair {
  const _DevAccountRepair({
    required this.reservationRepaired,
    required this.projectionRepaired,
  });

  final bool reservationRepaired;
  final bool projectionRepaired;
}

class DevBootstrapService {
  DevBootstrapService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String division = 'dev';
  static const String area = 'dev';
  static const String areaDocumentId = 'dev-dev';

  final FirebaseFirestore _firestore;

  void _record(String event, {Map<String, Object?> meta = const {}}) {
    ParkinWorkinTerminalDiagnostics.record(
      event,
      context: 'launcher_dev_bootstrap',
      meta: meta,
    );
  }

  void _verifySession(String email) {
    if (!DeveloperAccountAuthorization.isAuthorized) {
      throw const DevBootstrapException('개발자 인증을 다시 확인하세요.');
    }
    final identity = GoogleAuthSession.instance.currentIdentity;
    final currentUser = FirebaseGoogleAuthBridge.instance.currentUser;
    final normalized = email.trim().toLowerCase();
    if (identity == null ||
        currentUser == null ||
        currentUser.isAnonymous ||
        normalized.isEmpty ||
        identity.normalizedEmail != normalized ||
        currentUser.email?.trim().toLowerCase() != normalized) {
      throw const DevBootstrapException('연결된 계정을 먼저 확인하세요.');
    }
  }

  Future<DevBootstrapResult> ensure({required String email}) async {
    _verifySession(email);
    _record('dev_bootstrap_started');
    try {
      final settings = DevAreaSettingsDraft(
        englishName: area,
        modes: DevAreaModePolicy.headquarterModes,
        capabilities: Capability.values.toSet(),
      );
      final fallbackCode = AccountCodeNumber.generate();
      final fallbackAccountId = AccountCodeNumber.documentId(
        codeNumber: fallbackCode,
        area: area,
      );
      final divisionRef = _firestore.collection('divisions').doc(division);
      final areaRef = _firestore.collection('areas').doc(areaDocumentId);
      final metaRef =
          _firestore.collection('user_accounts_show').doc(areaDocumentId);

      final scaffold = await _firestore.runTransaction<_DevScaffold>((tx) async {
        final divisionSnap = await tx.get(divisionRef).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
        final areaSnap = await tx.get(areaRef).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
        final metaSnap = await tx.get(metaRef).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
        final divisionData = divisionSnap.data() ?? <String, dynamic>{};
        final areaData = areaSnap.data() ?? <String, dynamic>{};
        final metaData = metaSnap.data() ?? <String, dynamic>{};

        if (divisionSnap.exists &&
            ((divisionData['name']?.toString().trim() ?? '') != division ||
                (divisionData['companyId'] != null &&
                    divisionData['companyId'] != division))) {
          throw const DevBootstrapException('기존 개발 회사 정보가 일치하지 않습니다.');
        }
        if (divisionData['accountWriteLocked'] == true) {
          throw const DevBootstrapException('개발 회사의 계정 쓰기가 잠겨 있습니다.');
        }
        final accountId = divisionSnap.exists
            ? (divisionData['initialAdminAccountId'] ?? '').toString().trim()
            : fallbackAccountId;
        final suffix = '-$area';
        if (!accountId.endsWith(suffix) ||
            !AccountCodeNumber.isValid(
              accountId.substring(0, accountId.length - suffix.length),
            )) {
          throw const DevBootstrapException(
            '기존 회사의 초기 관리자 계정 참조를 확인해야 합니다.',
          );
        }
        final existingAccountSnap = await tx.get(
          _firestore.collection('user_accounts').doc(accountId),
        ).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
        if (existingAccountSnap.exists) {
          _verifyExistingAccount(
            existingAccountSnap.data()!,
            accountId.substring(0, accountId.length - suffix.length),
            email,
          );
        }
        final existingProjectionSnap = await tx.get(
          metaRef.collection('users').doc(accountId),
        ).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
        if (!metaSnap.exists && existingProjectionSnap.exists) {
          throw const DevBootstrapException(
            '기존 계정 조회 문서의 메타가 없어 자동 초기화하지 않습니다.',
          );
        }
        if (areaSnap.exists &&
            (areaData['division'] != division ||
                areaData['name'] != area ||
                areaData['isHeadquarter'] != true)) {
          throw const DevBootstrapException('기존 개발 지역 정보가 일치하지 않습니다.');
        }
        if (metaSnap.exists &&
            (metaData['division'] != division || metaData['area'] != area)) {
          throw const DevBootstrapException('기존 개발 지역 정보가 일치하지 않습니다.');
        }

        if (!divisionSnap.exists) {
          FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/launcher/application/dev_bootstrap_service.dart', result: 'staged');
          tx.set(divisionRef, <String, dynamic>{
            'name': division,
            'companyId': division,
            'accountWriteLocked': false,
            'accountWriteVersion': 0,
            'areaConfigVersion': 0,
            'initialAdminAccountId': accountId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        if (!areaSnap.exists) {
          FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/launcher/application/dev_bootstrap_service.dart', result: 'staged');
          tx.set(
            areaRef,
            settings.headquarterAreaPayload(
              name: area,
              division: division,
            ),
          );
        }
        if (!metaSnap.exists) {
          FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/launcher/application/dev_bootstrap_service.dart', result: 'staged');
          tx.set(
            metaRef,
            settings.accountMetaPayload(
              division: division,
              area: area,
            ),
          );
        }
        return _DevScaffold(
          accountId: accountId,
          divisionCreated: !divisionSnap.exists,
          areaCreated: !areaSnap.exists,
          metaCreated: !metaSnap.exists,
        );
      }).trackFirestore('TRANSACTION', 'features/launcher/application/dev_bootstrap_service.dart');

      _record('dev_bootstrap_scaffold_ready', meta: <String, Object?>{
        'divisionCreated': scaffold.divisionCreated,
        'areaCreated': scaffold.areaCreated,
        'metaCreated': scaffold.metaCreated,
      });
      _verifySession(email);

      final accountId = scaffold.accountId;
      final codeNumber = accountId.substring(0, accountId.length - 4);
      final rootRef = _firestore.collection('user_accounts').doc(accountId);
      final codeRef = _firestore.collection('user_account_codes').doc(codeNumber);
      final showUserRef = metaRef;
      final rootSnap = await rootRef.get(const GetOptions(source: Source.server)).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
      var accountCreated = false;
      var reservationRepaired = false;
      var projectionRepaired = false;

      if (rootSnap.exists) {
        _verifyExistingAccount(rootSnap.data()!, codeNumber, email);
        final repaired = await _repairExistingAccount(
          rootRef: rootRef,
          codeRef: codeRef,
          metaRef: metaRef,
          codeNumber: codeNumber,
          email: email,
        );
        reservationRepaired = repaired.reservationRepaired;
        projectionRepaired = repaired.projectionRepaired;
      } else {
        final codeSnap =
            await codeRef.get(const GetOptions(source: Source.server)).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
        final showUserSnap =
            await showUserRef.get(const GetOptions(source: Source.server)).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
        final showEntry = UserAccountShowMap.account(showUserSnap.data(), accountId);
        if (codeSnap.exists || showEntry != null) {
          throw const DevBootstrapException(
            '이미 사용 중인 계정 코드 또는 조회 문서가 있습니다.',
          );
        }
        final user = UserModel(
          id: accountId,
          areas: const <String>[area],
          currentArea: area,
          divisions: const <String>[division],
          modes: DevAreaModePolicy.canonicalModes,
          email: email.trim().toLowerCase(),
          englishSelectedAreaName: area,
          isSaved: false,
          isSelected: false,
          isWorking: false,
          name: 'dev',
          codeNumber: codeNumber,
          role: 'headAdmin',
          selectedArea: area,
          isActive: true,
        );
        _verifySession(email);
        try {
          await DevUserWriteService(firestore: _firestore).createUser(
            user: user,
            division: division,
            area: area,
            log: (message) => _record(
              'dev_bootstrap_account_write_step',
              meta: <String, Object?>{
                'step': SecureAuthDiagnostics.redact(message),
              },
            ),
          );
          accountCreated = true;
        } on StateError catch (error) {
          final code = error.toString();
          if (!code.contains('USER_ALREADY_EXISTS') &&
              !code.contains('CODE_NUMBER_ALREADY_EXISTS')) {
            rethrow;
          }
          final concurrentSnap =
              await rootRef.get(const GetOptions(source: Source.server)).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
          if (!concurrentSnap.exists) rethrow;
          _verifyExistingAccount(concurrentSnap.data()!, codeNumber, email);
          final repaired = await _repairExistingAccount(
            rootRef: rootRef,
            codeRef: codeRef,
            metaRef: metaRef,
              codeNumber: codeNumber,
            email: email,
          );
          reservationRepaired = repaired.reservationRepaired;
          projectionRepaired = repaired.projectionRepaired;
        }
      }
      final result = DevBootstrapResult(
        codeNumber: codeNumber,
        divisionCreated: scaffold.divisionCreated,
        areaCreated: scaffold.areaCreated,
        metaCreated: scaffold.metaCreated,
        accountCreated: accountCreated,
        reservationRepaired: reservationRepaired,
        projectionRepaired: projectionRepaired,
      );
      AccountRoleDiagnostics.record(
        'dev_bootstrap_map_complete writes=${result.writeOperations} accountCreated=$accountCreated projectionRepaired=$projectionRepaired',
      );
      _record('dev_bootstrap_completed', meta: <String, Object?>{
        'writeOperations': result.writeOperations,
        'reusedAccount': !accountCreated,
      });
      return result;
    } catch (error) {
      _record('dev_bootstrap_failed', meta: <String, Object?>{
        'errorType': error.runtimeType.toString(),
      });
      rethrow;
    }
  }

  void _verifyExistingAccount(
    Map<String, dynamic> data,
    String codeNumber,
    String email,
  ) {
    final accountAreas = data['areas'];
    final accountDivisions = data['divisions'];
    if (data['name'] != 'dev' ||
        AccountCodeNumber.normalize((data['codeNumber'] ?? '').toString()) !=
            codeNumber ||
        (data['email'] ?? '').toString().trim().toLowerCase() !=
            email.trim().toLowerCase() ||
        data['role'] != 'headAdmin' ||
        data['isActive'] != true ||
        accountAreas is! List ||
        !accountAreas.contains(area) ||
        accountDivisions is! List ||
        !accountDivisions.contains(division)) {
      throw const DevBootstrapException(
        '기존 초기 관리자 계정 정보가 다릅니다. 자동 덮어쓰기를 중단했습니다.',
      );
    }
  }

  Future<_DevAccountRepair> _repairExistingAccount({
    required DocumentReference<Map<String, dynamic>> rootRef,
    required DocumentReference<Map<String, dynamic>> codeRef,
    required DocumentReference<Map<String, dynamic>> metaRef,
    required String codeNumber,
    required String email,
  }) async {
    return _firestore.runTransaction<_DevAccountRepair>((tx) async {
      final rootSnap = await tx.get(rootRef).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
      final codeSnap = await tx.get(codeRef).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
      final metaSnap = await tx.get(metaRef).trackFirestore('GET', 'features/launcher/application/dev_bootstrap_service.dart');
      if (!rootSnap.exists || !metaSnap.exists) {
        throw const DevBootstrapException('개발 계정 원본 또는 메타가 없습니다.');
      }
      final rootData = rootSnap.data()!;
      _verifyExistingAccount(rootData, codeNumber, email);
      if (codeSnap.exists &&
          (codeSnap.data()?['userId'] != rootRef.id ||
              codeSnap.data()?['area'] != area ||
              codeSnap.data()?['codeNumber'] != codeNumber)) {
        throw const DevBootstrapException('기존 코드번호 예약 정보가 충돌합니다.');
      }
      final projection = UserAccountShowMap.account(metaSnap.data(), rootRef.id) ?? <String, dynamic>{};
      if (projection.isNotEmpty &&
          (projection['codeNumber'] != codeNumber ||
              projection['name'] != 'dev' ||
              projection['isActive'] != true ||
              projection['role'] != 'headAdmin' ||
              (projection['email'] ?? '').toString().trim().toLowerCase() !=
                  email.trim().toLowerCase() ||
              projection['areas'] is! List ||
              !(projection['areas'] as List).contains(area) ||
              projection['divisions'] is! List ||
              !(projection['divisions'] as List).contains(division))) {
        throw const DevBootstrapException('기존 계정 조회 문서가 일치하지 않습니다.');
      }
      if (!codeSnap.exists) {
        FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/launcher/application/dev_bootstrap_service.dart', result: 'staged');
        tx.set(codeRef, <String, dynamic>{
          'userId': rootRef.id,
          'codeNumber': codeNumber,
          'area': area,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (projection.isEmpty) {
        final projection = UserAccountViewProjection.fromMap(rootData);
        projection['updatedAt'] = FieldValue.serverTimestamp();
        FirebaseActivityMeter.instance.record(service: 'firestore', operation: 'STAGE_SET', source: 'features/launcher/application/dev_bootstrap_service.dart', result: 'staged');
        tx.set(
          metaRef,
          UserAccountShowMap.putPayload(rootRef.id, projection),
          UserAccountShowMap.putOptions(rootRef.id),
        );
      }
      return _DevAccountRepair(
        reservationRepaired: !codeSnap.exists,
        projectionRepaired: projection.isEmpty,
      );
    }).trackFirestore('TRANSACTION', 'features/launcher/application/dev_bootstrap_service.dart');
  }
}
