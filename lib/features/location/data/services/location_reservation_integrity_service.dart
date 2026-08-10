import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/location_model.dart';

enum LocationReservationIntegrityIssueType {
  orphan,
  missing,
  wrongOwner,
  staleMetadata,
  areaMismatch,
  invalidParent,
  invalidArea,
  duplicateOwner,
  invalidReservation,
  documentIdMismatch,
  duplicateReservation,
}

class LocationReservationIntegrityIssue {
  const LocationReservationIntegrityIssue({
    required this.type,
    required this.parentId,
    required this.parentName,
    required this.areaId,
    required this.expectedChildId,
    required this.expectedChildName,
    required this.actualChildId,
    required this.actualChildName,
    required this.reservationDocumentId,
    required this.detail,
  });

  final LocationReservationIntegrityIssueType type;
  final String parentId;
  final String parentName;
  final String areaId;
  final String expectedChildId;
  final String expectedChildName;
  final String actualChildId;
  final String actualChildName;
  final String reservationDocumentId;
  final String detail;

  String get label {
    switch (type) {
      case LocationReservationIntegrityIssueType.orphan:
        return 'ORPHAN';
      case LocationReservationIntegrityIssueType.missing:
        return 'MISSING';
      case LocationReservationIntegrityIssueType.wrongOwner:
        return 'WRONG_OWNER';
      case LocationReservationIntegrityIssueType.staleMetadata:
        return 'STALE_METADATA';
      case LocationReservationIntegrityIssueType.areaMismatch:
        return 'AREA_MISMATCH';
      case LocationReservationIntegrityIssueType.invalidParent:
        return 'INVALID_PARENT';
      case LocationReservationIntegrityIssueType.invalidArea:
        return 'INVALID_AREA';
      case LocationReservationIntegrityIssueType.duplicateOwner:
        return 'DUPLICATE_OWNER';
      case LocationReservationIntegrityIssueType.invalidReservation:
        return 'INVALID_RESERVATION';
      case LocationReservationIntegrityIssueType.documentIdMismatch:
        return 'DOCUMENT_ID_MISMATCH';
      case LocationReservationIntegrityIssueType.duplicateReservation:
        return 'DUPLICATE_RESERVATION';
    }
  }

  String toLogLine() {
    final parts = <String>[
      '[$label]',
      if (parentId.isNotEmpty) 'parentId=$parentId',
      if (parentName.isNotEmpty) 'parentName=$parentName',
      if (areaId.isNotEmpty) 'areaId=$areaId',
      if (expectedChildId.isNotEmpty) 'expectedChildId=$expectedChildId',
      if (expectedChildName.isNotEmpty)
        'expectedChildName=$expectedChildName',
      if (actualChildId.isNotEmpty) 'actualChildId=$actualChildId',
      if (actualChildName.isNotEmpty) 'actualChildName=$actualChildName',
      if (reservationDocumentId.isNotEmpty)
        'reservationDocumentId=$reservationDocumentId',
      if (detail.isNotEmpty) 'detail=$detail',
    ];
    return parts.join(' | ');
  }
}

class LocationReservationIntegrityReport {
  const LocationReservationIntegrityReport({
    required this.area,
    required this.locationCount,
    required this.parentCount,
    required this.childCount,
    required this.reservationCount,
    required this.expectedReservationCount,
    required this.normalCount,
    required this.issues,
  });

  final String area;
  final int locationCount;
  final int parentCount;
  final int childCount;
  final int reservationCount;
  final int expectedReservationCount;
  final int normalCount;
  final List<LocationReservationIntegrityIssue> issues;

  bool get hasIssues => issues.isNotEmpty;

  int count(LocationReservationIntegrityIssueType type) {
    return issues.where((issue) => issue.type == type).length;
  }

  int get blockingConflictCount {
    return count(LocationReservationIntegrityIssueType.invalidParent) +
        count(LocationReservationIntegrityIssueType.invalidArea) +
        count(LocationReservationIntegrityIssueType.duplicateOwner);
  }
}

class LocationReservationIntegrityService {
  LocationReservationIntegrityService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static String _normalizedName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String _encodedSegment(String value) {
    return base64Url.encode(utf8.encode(value.trim())).replaceAll('=', '');
  }

  static String _reservationDocumentId(String parentId, String areaId) {
    return '${_encodedSegment(parentId)}_${_encodedSegment(areaId)}';
  }

  static String _logicalKey(String parentId, String areaId) {
    return '${parentId.trim()}\u0000${areaId.trim()}';
  }

  static List<String> _slotAreaIds(LocationModel child) {
    final values = <String>[];
    final seen = <String>{};
    for (final value in child.childSlotAreaIds) {
      final clean = value.trim();
      if (clean.isEmpty || !seen.add(clean)) continue;
      values.add(clean);
    }
    if (values.isNotEmpty) return values;
    for (final slot in child.childSlots) {
      final clean = slot.areaId.trim();
      if (clean.isEmpty || !seen.add(clean)) continue;
      values.add(clean);
    }
    return values;
  }

  Future<LocationReservationIntegrityReport> check({
    required String area,
    void Function(String message, double progress)? onProgress,
  }) async {
    final cleanArea = area.trim();
    if (cleanArea.isEmpty) {
      throw StateError('현재 지역이 설정되지 않았습니다.');
    }

    onProgress?.call('현재 지역 확인: area=$cleanArea', 0.08);
    onProgress?.call('locations 서버 조회를 시작합니다.', 0.14);

    final locationSnapshot = await _firestore
        .collection('locations')
        .where('area', isEqualTo: cleanArea)
        .get(const GetOptions(source: Source.server));

    final locations = <LocationModel>[];
    for (final document in locationSnapshot.docs) {
      try {
        locations.add(LocationModel.fromMap(document.id, document.data()));
      } catch (error) {
        throw StateError(
          'locations 문서 파싱 실패: documentId=${document.id}, error=$error',
        );
      }
    }

    final parents = locations.where((location) => location.isCompositeParent)
        .toList(growable: false);
    final children = locations.where((location) => location.isCompositeChild)
        .toList(growable: false);
    final parentsById = <String, LocationModel>{
      for (final parent in parents) parent.id: parent,
    };
    final parentsByName = <String, List<LocationModel>>{};
    for (final parent in parents) {
      final key = _normalizedName(parent.locationName);
      if (key.isEmpty) continue;
      parentsByName.putIfAbsent(key, () => <LocationModel>[]).add(parent);
    }

    onProgress?.call(
      'locations 서버 조회 완료: documents=${locations.length}, parents=${parents.length}, children=${children.length}',
      0.28,
    );
    onProgress?.call('locations 기준 예상 예약을 계산합니다.', 0.34);

    final issues = <LocationReservationIntegrityIssue>[];
    final expectedByKey = <String, _ExpectedReservation>{};
    final conflictedExpectedKeys = <String>{};

    for (final child in children) {
      if (child.isTowerChild) continue;

      final storedParentId = (child.parentId ?? '').trim();
      LocationModel? parent;
      if (storedParentId.isNotEmpty) {
        parent = parentsById[storedParentId];
      }
      if (parent == null) {
        final legacyParentName = (child.parent ?? '').trim();
        final candidates =
            parentsByName[_normalizedName(legacyParentName)] ??
                const <LocationModel>[];
        if (candidates.length == 1) {
          parent = candidates.first;
        }
      }

      final slotAreaIds = _slotAreaIds(child);
      if (parent == null) {
        if (slotAreaIds.isNotEmpty) {
          issues.add(
            LocationReservationIntegrityIssue(
              type: LocationReservationIntegrityIssueType.invalidParent,
              parentId: storedParentId,
              parentName: (child.parent ?? '').trim(),
              areaId: slotAreaIds.join(','),
              expectedChildId: child.id,
              expectedChildName: child.locationName.trim(),
              actualChildId: '',
              actualChildName: '',
              reservationDocumentId: '',
              detail: '자식 구역의 부모 문서를 확인할 수 없습니다.',
            ),
          );
        }
        continue;
      }

      final parentAreaIds = parent.parkingGrid?.parkingAreas
              .map((parkingArea) => parkingArea.id.trim())
              .where((value) => value.isNotEmpty)
              .toSet() ??
          <String>{};

      for (final areaId in slotAreaIds) {
        if (!parentAreaIds.contains(areaId)) {
          issues.add(
            LocationReservationIntegrityIssue(
              type: LocationReservationIntegrityIssueType.invalidArea,
              parentId: parent.id,
              parentName: parent.locationName.trim(),
              areaId: areaId,
              expectedChildId: child.id,
              expectedChildName: child.locationName.trim(),
              actualChildId: '',
              actualChildName: '',
              reservationDocumentId: '',
              detail: '자식 슬롯이 부모 parkingGrid.parkingAreas에 존재하지 않습니다.',
            ),
          );
          continue;
        }

        final key = _logicalKey(parent.id, areaId);
        final expected = _ExpectedReservation(
          parentId: parent.id,
          parentName: parent.locationName.trim(),
          childId: child.id,
          childName: child.locationName.trim(),
          areaId: areaId,
        );
        final previous = expectedByKey[key];
        if (previous != null && previous.childId != expected.childId) {
          conflictedExpectedKeys.add(key);
          issues.add(
            LocationReservationIntegrityIssue(
              type: LocationReservationIntegrityIssueType.duplicateOwner,
              parentId: parent.id,
              parentName: parent.locationName.trim(),
              areaId: areaId,
              expectedChildId: '${previous.childId},${expected.childId}',
              expectedChildName:
                  '${previous.childName},${expected.childName}',
              actualChildId: '',
              actualChildName: '',
              reservationDocumentId: '',
              detail: 'locations의 서로 다른 자식 구역이 같은 주차면을 사용합니다.',
            ),
          );
          continue;
        }
        expectedByKey[key] = expected;
      }
    }

    onProgress?.call(
      '예상 예약 계산 완료: expectedReservations=${expectedByKey.length}, blockingConflicts=${issues.length}',
      0.46,
    );
    onProgress?.call('locationSlotReservations 서버 조회를 시작합니다.', 0.52);

    final reservationDocuments = <String, _ReservationDocument>{};
    final reservationCollection =
        _firestore.collection('locationSlotReservations');

    final areaReservationSnapshot = await reservationCollection
        .where('area', isEqualTo: cleanArea)
        .get(const GetOptions(source: Source.server));
    for (final document in areaReservationSnapshot.docs) {
      reservationDocuments[document.id] = _ReservationDocument(
        id: document.id,
        data: document.data(),
      );
    }

    var parentScopedReadCount = 0;
    for (final parent in parents) {
      final parentReservationSnapshot = await reservationCollection
          .where('parentId', isEqualTo: parent.id)
          .get(const GetOptions(source: Source.server));
      parentScopedReadCount += parentReservationSnapshot.docs.length;
      for (final document in parentReservationSnapshot.docs) {
        reservationDocuments[document.id] = _ReservationDocument(
          id: document.id,
          data: document.data(),
        );
      }
    }

    final parentAreaById = <String, String>{
      for (final parent in parents) parent.id: cleanArea,
    };
    final unresolvedParentIds = <String>{};
    for (final document in reservationDocuments.values) {
      final parentId = (document.data['parentId'] ?? '').toString().trim();
      if (parentId.isEmpty || parentAreaById.containsKey(parentId)) continue;
      unresolvedParentIds.add(parentId);
    }

    var resolvedForeignParentCount = 0;
    for (final parentId in unresolvedParentIds) {
      final parentSnapshot = await _firestore
          .collection('locations')
          .doc(parentId)
          .get(const GetOptions(source: Source.server));
      if (!parentSnapshot.exists) continue;
      final data = parentSnapshot.data();
      if (data == null) continue;
      final type = (data['type'] ?? '').toString().trim();
      final parentArea = (data['area'] ?? '').toString().trim();
      if (type != 'composite_parent' || parentArea.isEmpty) continue;
      parentAreaById[parentId] = parentArea;
      resolvedForeignParentCount++;
    }

    onProgress?.call(
      'locationSlotReservations 서버 조회 완료: areaQuery=${areaReservationSnapshot.docs.length}, parentScopedReads=$parentScopedReadCount, mergedDocuments=${reservationDocuments.length}, resolvedForeignParents=$resolvedForeignParentCount',
      0.64,
    );

    final actualByKey = <String, _ActualReservation>{};
    final actualKeysWithStructuralIssue = <String>{};
    final actualKeysWithComparisonIssue = <String>{};
    final actualParentAreaByKey = <String, String>{};

    for (final document in reservationDocuments.values) {
      final data = document.data;
      final parentId = (data['parentId'] ?? '').toString().trim();
      final areaId = (data['areaId'] ?? '').toString().trim();
      final parentName = (data['parentName'] ?? '').toString().trim();
      final childId = (data['childId'] ?? '').toString().trim();
      final childName = (data['childName'] ?? '').toString().trim();
      final reservationArea = (data['area'] ?? '').toString().trim();
      final resolvedParentArea = parentAreaById[parentId] ?? '';

      if (resolvedParentArea.isNotEmpty && reservationArea != resolvedParentArea) {
        issues.add(
          LocationReservationIntegrityIssue(
            type: LocationReservationIntegrityIssueType.areaMismatch,
            parentId: parentId,
            parentName: parentName,
            areaId: areaId,
            expectedChildId: '',
            expectedChildName: '',
            actualChildId: childId,
            actualChildName: childName,
            reservationDocumentId: document.id,
            detail:
                'expectedArea=$resolvedParentArea, actualArea=$reservationArea',
          ),
        );
      }

      if (parentId.isEmpty || areaId.isEmpty) {
        issues.add(
          LocationReservationIntegrityIssue(
            type: LocationReservationIntegrityIssueType.invalidReservation,
            parentId: parentId,
            parentName: parentName,
            areaId: areaId,
            expectedChildId: '',
            expectedChildName: '',
            actualChildId: childId,
            actualChildName: childName,
            reservationDocumentId: document.id,
            detail: 'reservation 문서의 parentId 또는 areaId가 비어 있습니다.',
          ),
        );
        continue;
      }

      final key = _logicalKey(parentId, areaId);
      actualParentAreaByKey[key] = resolvedParentArea;
      if (resolvedParentArea.isNotEmpty && reservationArea != resolvedParentArea) {
        actualKeysWithComparisonIssue.add(key);
      }
      final expectedDocumentId = _reservationDocumentId(parentId, areaId);
      if (document.id != expectedDocumentId) {
        actualKeysWithStructuralIssue.add(key);
        issues.add(
          LocationReservationIntegrityIssue(
            type: LocationReservationIntegrityIssueType.documentIdMismatch,
            parentId: parentId,
            parentName: parentName,
            areaId: areaId,
            expectedChildId: '',
            expectedChildName: '',
            actualChildId: childId,
            actualChildName: childName,
            reservationDocumentId: document.id,
            detail: 'expectedDocumentId=$expectedDocumentId',
          ),
        );
      }

      final current = _ActualReservation(
        documentId: document.id,
        parentId: parentId,
        parentName: parentName,
        childId: childId,
        childName: childName,
        areaId: areaId,
      );
      final previous = actualByKey[key];
      if (previous != null) {
        actualKeysWithStructuralIssue.add(key);
        issues.add(
          LocationReservationIntegrityIssue(
            type: LocationReservationIntegrityIssueType.duplicateReservation,
            parentId: parentId,
            parentName: parentName,
            areaId: areaId,
            expectedChildId: '',
            expectedChildName: '',
            actualChildId: '$childId,${previous.childId}',
            actualChildName: '$childName,${previous.childName}',
            reservationDocumentId: '${previous.documentId},${document.id}',
            detail: '같은 parentId + areaId 조합의 reservation 문서가 중복됩니다.',
          ),
        );
        if (document.id == expectedDocumentId &&
            previous.documentId != expectedDocumentId) {
          actualByKey[key] = current;
        }
        continue;
      }
      actualByKey[key] = current;
    }

    onProgress?.call('locations와 예약 문서를 비교합니다.', 0.72);

    var normalCount = 0;

    for (final entry in expectedByKey.entries) {
      final key = entry.key;
      final expected = entry.value;
      if (conflictedExpectedKeys.contains(key)) continue;
      final actual = actualByKey[key];
      if (actual == null) {
        issues.add(
          LocationReservationIntegrityIssue(
            type: LocationReservationIntegrityIssueType.missing,
            parentId: expected.parentId,
            parentName: expected.parentName,
            areaId: expected.areaId,
            expectedChildId: expected.childId,
            expectedChildName: expected.childName,
            actualChildId: '',
            actualChildName: '',
            reservationDocumentId:
                _reservationDocumentId(expected.parentId, expected.areaId),
            detail: 'locations에는 배정이 있지만 reservation 문서가 없습니다.',
          ),
        );
        continue;
      }

      if (actual.childId != expected.childId) {
        actualKeysWithComparisonIssue.add(key);
        issues.add(
          LocationReservationIntegrityIssue(
            type: LocationReservationIntegrityIssueType.wrongOwner,
            parentId: expected.parentId,
            parentName: expected.parentName,
            areaId: expected.areaId,
            expectedChildId: expected.childId,
            expectedChildName: expected.childName,
            actualChildId: actual.childId,
            actualChildName: actual.childName,
            reservationDocumentId: actual.documentId,
            detail: 'reservation의 childId가 locations 기준 소유자와 다릅니다.',
          ),
        );
      }

      final metadataMatches = actual.parentName == expected.parentName &&
          actual.childName == expected.childName;
      if (!metadataMatches) {
        actualKeysWithComparisonIssue.add(key);
        issues.add(
          LocationReservationIntegrityIssue(
            type: LocationReservationIntegrityIssueType.staleMetadata,
            parentId: expected.parentId,
            parentName: expected.parentName,
            areaId: expected.areaId,
            expectedChildId: expected.childId,
            expectedChildName: expected.childName,
            actualChildId: actual.childId,
            actualChildName: actual.childName,
            reservationDocumentId: actual.documentId,
            detail:
                'actualParentName=${actual.parentName}, actualChildName=${actual.childName}',
          ),
        );
      }

      if (!actualKeysWithStructuralIssue.contains(key) &&
          !actualKeysWithComparisonIssue.contains(key)) {
        normalCount++;
      }
    }

    for (final entry in actualByKey.entries) {
      if (expectedByKey.containsKey(entry.key)) continue;
      final actual = entry.value;
      final resolvedParentArea = actualParentAreaByKey[entry.key] ?? '';
      if (resolvedParentArea.isNotEmpty && resolvedParentArea != cleanArea) {
        continue;
      }
      issues.add(
        LocationReservationIntegrityIssue(
          type: LocationReservationIntegrityIssueType.orphan,
          parentId: actual.parentId,
          parentName: actual.parentName,
          areaId: actual.areaId,
          expectedChildId: '',
          expectedChildName: '',
          actualChildId: actual.childId,
          actualChildName: actual.childName,
          reservationDocumentId: actual.documentId,
          detail: 'reservation은 존재하지만 locations 기준 슬롯 소유자가 없습니다.',
        ),
      );
    }

    final report = LocationReservationIntegrityReport(
      area: cleanArea,
      locationCount: locations.length,
      parentCount: parents.length,
      childCount: children.length,
      reservationCount: reservationDocuments.length,
      expectedReservationCount: expectedByKey.length,
      normalCount: normalCount,
      issues: List<LocationReservationIntegrityIssue>.unmodifiable(issues),
    );

    onProgress?.call(
      '정합성 비교 완료: normal=${report.normalCount}, issues=${report.issues.length}, blockingConflicts=${report.blockingConflictCount}',
      0.84,
    );

    return report;
  }
}

class _ReservationDocument {
  const _ReservationDocument({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;
}

class _ExpectedReservation {
  const _ExpectedReservation({
    required this.parentId,
    required this.parentName,
    required this.childId,
    required this.childName,
    required this.areaId,
  });

  final String parentId;
  final String parentName;
  final String childId;
  final String childName;
  final String areaId;
}

class _ActualReservation {
  const _ActualReservation({
    required this.documentId,
    required this.parentId,
    required this.parentName,
    required this.childId,
    required this.childName,
    required this.areaId,
  });

  final String documentId;
  final String parentId;
  final String parentName;
  final String childId;
  final String childName;
  final String areaId;
}
