import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../shared/auth/account_code_number.dart';

typedef LegacyAccountMigrationLogger = void Function(
  String message,
  double progress,
);

enum _LegacyMigrationAction {
  generatedAndMoved,
  moved,
  cleaned,
  skipped,
}

class _LegacyMigrationStepResult {
  const _LegacyMigrationStepResult({
    required this.action,
    required this.codeNumber,
    required this.area,
  });

  final _LegacyMigrationAction action;
  final String codeNumber;
  final String area;
}

class LegacyAccountMigrationResult {
  const LegacyAccountMigrationResult({
    required this.collection,
    required this.total,
    required this.generated,
    required this.moved,
    required this.cleaned,
    required this.skipped,
    required this.failed,
  });

  final String collection;
  final int total;
  final int generated;
  final int moved;
  final int cleaned;
  final int skipped;
  final int failed;

  int get changed => generated + moved + cleaned;

  String get summary =>
      '전체 $total개 · 신규 코드 발급 $generated개 · 문서 이동 $moved개 · 레거시 필드 정리 $cleaned개 · 유지 $skipped개 · 실패 $failed개';
}

class LegacyAccountCodeNumberMigrationService {
  LegacyAccountCodeNumberMigrationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<LegacyAccountMigrationResult> migrateTabletAccounts({
    LegacyAccountMigrationLogger? onLog,
  }) {
    return _migrateCollection(
      collectionName: 'tablet_accounts',
      legacyFields: const <String>['phone', 'handle'],
      onLog: onLog,
    );
  }

  Future<LegacyAccountMigrationResult> migratePersonalAccounts({
    LegacyAccountMigrationLogger? onLog,
  }) {
    return _migrateCollection(
      collectionName: 'personal_accounts',
      legacyFields: const <String>['phone', 'personalPhone', 'handle'],
      onLog: onLog,
    );
  }

  Future<LegacyAccountMigrationResult> _migrateCollection({
    required String collectionName,
    required List<String> legacyFields,
    LegacyAccountMigrationLogger? onLog,
  }) async {
    final collection = _firestore.collection(collectionName);
    onLog?.call('$collectionName 전체 계정 조회를 시작합니다.', 0.04);
    final snapshot = await collection.get();
    final usedCodes = <String>{};
    for (final doc in snapshot.docs) {
      final code = AccountCodeNumber.normalize(
        (doc.data()['codeNumber'] ?? '').toString(),
      );
      if (AccountCodeNumber.isGeneratedCode(code)) {
        usedCodes.add(code);
      }
    }

    var generated = 0;
    var moved = 0;
    var cleaned = 0;
    var skipped = 0;
    var failed = 0;
    final total = snapshot.docs.length;

    if (total == 0) {
      onLog?.call('$collectionName에 마이그레이션할 계정이 없습니다.', 1);
      return LegacyAccountMigrationResult(
        collection: collectionName,
        total: 0,
        generated: 0,
        moved: 0,
        cleaned: 0,
        skipped: 0,
        failed: 0,
      );
    }

    for (var index = 0; index < snapshot.docs.length; index += 1) {
      final source = snapshot.docs[index];
      final initialData = source.data();
      final progress = 0.08 + ((index + 1) / total) * 0.86;
      String? allocatedCodeNumber;

      try {
        final initialCodeNumber = AccountCodeNumber.normalize(
          (initialData['codeNumber'] ?? '').toString(),
        );

        final proposedCodeNumber =
            AccountCodeNumber.isGeneratedCode(initialCodeNumber)
                ? initialCodeNumber
                : await _allocateCodeNumber(
                    collection: collection,
                    usedCodes: usedCodes,
                  );

        if (!AccountCodeNumber.isGeneratedCode(initialCodeNumber)) {
          allocatedCodeNumber = proposedCodeNumber;
        } else {
          usedCodes.add(proposedCodeNumber);
        }

        final result = await _migrateSourceDocument(
          collection: collection,
          sourceReference: source.reference,
          sourceId: source.id,
          proposedCodeNumber: proposedCodeNumber,
          legacyFields: legacyFields,
        );

        if (allocatedCodeNumber != null &&
            allocatedCodeNumber != result.codeNumber) {
          usedCodes.remove(allocatedCodeNumber);
        }
        usedCodes.add(result.codeNumber);

        switch (result.action) {
          case _LegacyMigrationAction.generatedAndMoved:
            generated += 1;
            onLog?.call(
              '$collectionName 신규 코드 발급 및 이동: ${source.id} → ${AccountCodeNumber.format(result.codeNumber)}-${result.area}',
              progress,
            );
            break;
          case _LegacyMigrationAction.moved:
            moved += 1;
            onLog?.call(
              '$collectionName 문서 ID 정규화: ${source.id} → ${AccountCodeNumber.format(result.codeNumber)}-${result.area}',
              progress,
            );
            break;
          case _LegacyMigrationAction.cleaned:
            cleaned += 1;
            onLog?.call(
              '$collectionName 레거시 필드 정리: codeNumber=${AccountCodeNumber.format(result.codeNumber)} area=${result.area}',
              progress,
            );
            break;
          case _LegacyMigrationAction.skipped:
            skipped += 1;
            onLog?.call(
              '$collectionName 유지: codeNumber=${AccountCodeNumber.format(result.codeNumber)} area=${result.area}',
              progress,
            );
            break;
        }
      } catch (error) {
        if (allocatedCodeNumber != null) {
          usedCodes.remove(allocatedCodeNumber);
        }
        failed += 1;
        onLog?.call(
          '$collectionName 마이그레이션 실패: source=${source.id} error=$error',
          progress,
        );
      }
    }

    onLog?.call(
      '$collectionName 마이그레이션 완료: 신규=$generated 이동=$moved 정리=$cleaned 유지=$skipped 실패=$failed',
      1,
    );
    return LegacyAccountMigrationResult(
      collection: collectionName,
      total: total,
      generated: generated,
      moved: moved,
      cleaned: cleaned,
      skipped: skipped,
      failed: failed,
    );
  }

  Future<_LegacyMigrationStepResult> _migrateSourceDocument({
    required CollectionReference<Map<String, dynamic>> collection,
    required DocumentReference<Map<String, dynamic>> sourceReference,
    required String sourceId,
    required String proposedCodeNumber,
    required List<String> legacyFields,
  }) {
    return _firestore.runTransaction<_LegacyMigrationStepResult>(
      (transaction) async {
        final freshSource = await transaction.get(sourceReference);
        if (!freshSource.exists) {
          throw StateError('SOURCE_DOCUMENT_NOT_FOUND');
        }

        final freshData = freshSource.data();
        if (freshData == null) {
          throw StateError('SOURCE_DOCUMENT_DATA_NOT_FOUND');
        }

        final freshCodeNumber = AccountCodeNumber.normalize(
          (freshData['codeNumber'] ?? '').toString(),
        );
        final codeNumber = AccountCodeNumber.isGeneratedCode(freshCodeNumber)
            ? freshCodeNumber
            : proposedCodeNumber;
        if (!AccountCodeNumber.isGeneratedCode(codeNumber)) {
          throw StateError('INVALID_CODE_NUMBER');
        }

        final area = _resolveArea(freshData, sourceId);
        if (area.isEmpty) {
          throw StateError('AREA_NOT_FOUND');
        }

        final targetId = AccountCodeNumber.documentId(
          codeNumber: codeNumber,
          area: area,
        );
        if (targetId.isEmpty) {
          throw StateError('INVALID_TARGET_DOCUMENT_ID');
        }

        final fieldsToDelete = legacyFields
            .where((field) => freshData.containsKey(field))
            .toList(growable: false);

        if (sourceId == targetId) {
          final needsCodeUpdate = freshCodeNumber != codeNumber;
          if (!needsCodeUpdate && fieldsToDelete.isEmpty) {
            return _LegacyMigrationStepResult(
              action: _LegacyMigrationAction.skipped,
              codeNumber: codeNumber,
              area: area,
            );
          }

          final updates = <String, dynamic>{
            'codeNumber': codeNumber,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          for (final field in fieldsToDelete) {
            updates[field] = FieldValue.delete();
          }
          transaction.update(sourceReference, updates);
          return _LegacyMigrationStepResult(
            action: _LegacyMigrationAction.cleaned,
            codeNumber: codeNumber,
            area: area,
          );
        }

        final targetReference = collection.doc(targetId);
        final freshTarget = await transaction.get(targetReference);
        if (freshTarget.exists) {
          throw StateError('TARGET_DOCUMENT_CONFLICT');
        }

        final migratedData = Map<String, dynamic>.from(freshData)
          ..['codeNumber'] = codeNumber
          ..['updatedAt'] = FieldValue.serverTimestamp();
        for (final field in legacyFields) {
          migratedData.remove(field);
        }

        transaction.set(targetReference, migratedData);
        transaction.delete(sourceReference);

        return _LegacyMigrationStepResult(
          action: AccountCodeNumber.isGeneratedCode(freshCodeNumber)
              ? _LegacyMigrationAction.moved
              : _LegacyMigrationAction.generatedAndMoved,
          codeNumber: codeNumber,
          area: area,
        );
      },
    );
  }

  Future<String> _allocateCodeNumber({
    required CollectionReference<Map<String, dynamic>> collection,
    required Set<String> usedCodes,
  }) async {
    for (var attempt = 0; attempt < 24; attempt += 1) {
      final candidate = AccountCodeNumber.generate();
      if (usedCodes.contains(candidate)) continue;
      final duplicate = await collection
          .where('codeNumber', isEqualTo: candidate)
          .limit(1)
          .get();
      if (duplicate.docs.isNotEmpty) continue;
      usedCodes.add(candidate);
      return candidate;
    }
    throw StateError('CODE_NUMBER_GENERATION_FAILED');
  }

  String _resolveArea(Map<String, dynamic> data, String documentId) {
    for (final key in const <String>[
      'selectedArea',
      'currentArea',
      'area',
    ]) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    final areas = data['areas'];
    if (areas is Iterable) {
      for (final value in areas) {
        final area = value.toString().trim();
        if (area.isNotEmpty) return area;
      }
    }

    final codeNumber = AccountCodeNumber.normalize(
      (data['codeNumber'] ?? '').toString(),
    );
    if (AccountCodeNumber.isGeneratedCode(codeNumber)) {
      final prefix = '$codeNumber-';
      if (documentId.startsWith(prefix)) {
        return documentId.substring(prefix.length).trim();
      }
    }

    final legacyRaw = (data['phone'] ?? data['handle'] ?? '').toString();
    final legacyNormalized = legacyRaw.replaceAll(RegExp(r'[^0-9]'), '');
    if (legacyNormalized.isNotEmpty) {
      final prefix = '$legacyNormalized-';
      if (documentId.startsWith(prefix)) {
        return documentId.substring(prefix.length).trim();
      }
    }

    return '';
  }
}
