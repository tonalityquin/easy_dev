import '../../../../app/firebase_activity/firebase_activity_write_scope.dart';
import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/location_model.dart';
import '../../domain/models/parking_grid_model.dart';
import '../../domain/repositories/location_repository.dart';

class LocationWriteService {
  final FirebaseFirestore _firestore;

  LocationWriteService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  bool _isCompositeParent(LocationModel loc) =>
      (loc.type ?? '') == 'composite_parent';

  bool _isCompositeChild(LocationModel loc) {
    final type = loc.type ?? 'single';
    return type == 'composite_child' || type == 'composite';
  }

  void _validateParkingGrid(ParkingGridModel grid) {
    if (grid.rows <= 0 || grid.cols <= 0) {
      throw ArgumentError('parkingGrid rows/cols must be positive');
    }
    if (grid.cells.length != grid.rows * grid.cols) {
      throw ArgumentError('parkingGrid cells length mismatch');
    }

    final areas = grid.parkingAreas;
    if (areas.isEmpty) return;

    final rows = grid.rows;
    final cols = grid.cols;

    int indexOf(int row, int col) => row * cols + col;
    final used = <int>{};
    final ids = <String>{};

    for (final area in areas) {
      final id = area.id.trim();
      if (id.isEmpty) {
        throw ArgumentError('parkingArea id cannot be empty');
      }
      if (!ids.add(id)) {
        throw ArgumentError('duplicate parkingArea id: $id');
      }

      final top = area.r0 < area.r1 ? area.r0 : area.r1;
      final bottom = area.r0 < area.r1 ? area.r1 : area.r0;
      final left = area.c0 < area.c1 ? area.c0 : area.c1;
      final right = area.c0 < area.c1 ? area.c1 : area.c0;

      if (top < 0 || left < 0 || bottom >= rows || right >= cols) {
        throw ArgumentError('parkingArea out of bounds: $id');
      }

      for (var row = top; row <= bottom; row++) {
        for (var col = left; col <= right; col++) {
          final index = indexOf(row, col);
          if (!used.add(index)) {
            throw ArgumentError(
              'parkingAreas overlap (id=$id, cell=$row,$col)',
            );
          }
          if (grid.cells[index] != ParkingGridCellType.empty) {
            throw ArgumentError(
              'parkingArea must be on EMPTY cells only (id=$id, cell=$row,$col)',
            );
          }
        }
      }
    }
  }

  String _encodedSegment(String value) {
    return base64Url.encode(utf8.encode(value.trim())).replaceAll('=', '');
  }

  String _reservationId(String parentId, String areaId) {
    return '${_encodedSegment(parentId)}_${_encodedSegment(areaId)}';
  }

  DocumentReference<Map<String, dynamic>> _reservationRef(
    String parentId,
    String areaId,
  ) {
    return _firestore
        .collection('locationSlotReservations')
        .doc(_reservationId(parentId, areaId));
  }

  Set<String> _slotIds(LocationModel child) {
    final ids = <String>{};
    for (final raw in child.childSlotAreaIds) {
      final id = raw.trim();
      if (id.isNotEmpty) ids.add(id);
    }
    if (ids.isNotEmpty) return ids;
    for (final slot in child.childSlots) {
      final id = slot.areaId.trim();
      if (id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  Set<String> _slotIdsFromData(Map<String, dynamic>? data) {
    if (data == null) return <String>{};
    final ids = <String>{};
    final rawIds = data['childSlotAreaIds'];
    if (rawIds is List) {
      for (final raw in rawIds) {
        final id = raw.toString().trim();
        if (id.isNotEmpty) ids.add(id);
      }
    }
    if (ids.isNotEmpty) return ids;
    final rawSlots = data['childSlots'];
    if (rawSlots is List) {
      for (final raw in rawSlots) {
        if (raw is! Map) continue;
        final id = (raw['areaId'] ?? '').toString().trim();
        if (id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  Map<String, dynamic> _reservationData({
    required LocationModel parent,
    required LocationModel child,
    required String areaId,
  }) {
    if (parent.companyId.trim().isEmpty ||
        parent.companyId != child.companyId) {
      throw StateError('LOCATION_PARENT_CHILD_COMPANY_MISMATCH');
    }
    return <String, dynamic>{
      'companyId': child.companyId,
      'area': child.area,
      'parentId': parent.id,
      'parentName': parent.locationName,
      'childId': child.id,
      'childName': child.locationName,
      'areaId': areaId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _compositeChildData(LocationModel child) {
    final parentId = (child.parentId ?? '').trim();
    if (parentId.isEmpty) {
      throw ArgumentError('composite_child must have non-empty parentId');
    }

    if (child.companyId.trim().isEmpty) {
      throw StateError('LOCATION_COMPANY_ID_REQUIRED');
    }
    final data = child.toFirestoreMap();
    data['type'] = 'composite_child';
    data['parentId'] = parentId;
    data['updatedAt'] = FieldValue.serverTimestamp();
    data.remove('parkingGrid');
    if (child.childSlotAreaIds.isEmpty) {
      data['childSlotAreaIds'] = FieldValue.delete();
    }
    if (child.childSlots.isEmpty) {
      data['childSlots'] = FieldValue.delete();
    }
    return data;
  }

  Map<String, dynamic> _compositeParentData(LocationModel parent) {
    final grid = parent.parkingGrid;
    if (grid == null) {
      throw ArgumentError('composite_parent requires non-null parkingGrid');
    }

    _validateParkingGrid(grid);

    if (parent.companyId.trim().isEmpty) {
      throw StateError('LOCATION_COMPANY_ID_REQUIRED');
    }
    final data = parent.toFirestoreMap();
    data['type'] = 'composite_parent';
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['parkingGrid'] = grid.toJson();
    data['parentId'] = FieldValue.delete();
    data['parent'] = FieldValue.delete();
    data['childRect'] = FieldValue.delete();
    data['childKind'] = FieldValue.delete();
    data['childSlotAreaIds'] = FieldValue.delete();
    data['childSlots'] = FieldValue.delete();
    return data;
  }


  Future<void> createPlainTextLocation(LocationModel location) async {
    final locationName = location.locationName.trim();
    if (locationName.isEmpty) {
      throw ArgumentError('plain text locationName cannot be empty');
    }
    if ((location.type ?? 'single') != 'single') {
      throw ArgumentError('createPlainTextLocation requires type=single');
    }
    if (location.capacity < 0 || location.capacity > 9999) {
      throw ArgumentError('plain text capacity must be between 0 and 9999');
    }

    final ref = _firestore.collection('locations').doc(location.id);
    if (location.companyId.trim().isEmpty) {
      throw StateError('LOCATION_COMPANY_ID_REQUIRED');
    }
    final data = location.toFirestoreMap();
    data['type'] = 'single';
    data['isSelected'] = false;
    data['plateCount'] = location.plateCount;
    data['updatedAt'] = FieldValue.serverTimestamp();
    data.remove('parentId');
    data.remove('parent');
    data.remove('parkingGrid');
    data.remove('childRect');
    data.remove('childKind');
    data.remove('childSlotAreaIds');
    data.remove('childSlots');

    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((transaction) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(ref), source: 'location_write_service.get');
      if (snapshot.exists) {
        throw StateError('이미 존재하는 텍스트형 구역입니다.');
      }
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => transaction.set(ref, data));
    }), source: 'location_write_service.runTransaction');

    debugPrint(
      'createPlainTextLocation id=${location.id} area=${location.area} name=$locationName capacity=${location.capacity}',
    );
  }

  Future<void> createCompositeParent(LocationModel parent) async {
    if (!_isCompositeParent(parent)) {
      throw ArgumentError(
        'createCompositeParent requires type=composite_parent',
      );
    }

    final parentName = parent.locationName.trim();
    if (parentName.isEmpty) {
      throw ArgumentError('parent locationName cannot be empty');
    }

    final data = _compositeParentData(parent);
    final ref = _firestore.collection('locations').doc(parent.id);

    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((transaction) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(ref), source: 'location_write_service.get');
      if (snapshot.exists) {
        throw StateError('이미 존재하는 부모 구역입니다.');
      }
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => transaction.set(ref, data, SetOptions(merge: true)));
    }), source: 'location_write_service.runTransaction');

    debugPrint(
      'createCompositeParent id=${parent.id} area=${parent.area} name=$parentName',
    );
  }

  Future<void> updateCompositeParentWithChildren({
    required LocationModel parent,
    required List<LocationModel> children,
  }) async {
    if (!_isCompositeParent(parent)) {
      throw ArgumentError('parent must be type=composite_parent');
    }

    final parentData = _compositeParentData(parent);
    final parentRef = _firestore.collection('locations').doc(parent.id);
    final childRefs = <String, DocumentReference<Map<String, dynamic>>>{
      for (final child in children)
        child.id: _firestore.collection('locations').doc(child.id),
    };
    final nextIdsByChild = <String, Set<String>>{};
    final nextOwnerByAreaId = <String, String>{};

    for (final child in children) {
      if (child.companyId != parent.companyId || child.area != parent.area) {
        throw StateError('LOCATION_PARENT_CHILD_SCOPE_MISMATCH');
      }
      if (!_isCompositeChild(child)) {
        throw ArgumentError(
          'child must be type=composite_child: ${child.id}',
        );
      }
      if ((child.parentId ?? '').trim() != parent.id) {
        throw ArgumentError('child parentId does not match parent id');
      }

      final nextIds = _slotIds(child);
      nextIdsByChild[child.id] = nextIds;
      for (final areaId in nextIds) {
        final previousOwner = nextOwnerByAreaId[areaId];
        if (previousOwner != null && previousOwner != child.id) {
          throw StateError('동일한 주차면이 여러 자식 구역에 배정되었습니다: $areaId');
        }
        nextOwnerByAreaId[areaId] = child.id;
      }
    }

    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((transaction) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      final parentSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(parentRef), source: 'location_write_service.get');
      if (!parentSnapshot.exists ||
          (parentSnapshot.data()?['type'] ?? '').toString() !=
              'composite_parent') {
        throw StateError('수정할 부모 구역이 없습니다.');
      }

      final previousSlotIdsByChild = <String, Set<String>>{};
      for (final child in children) {
        final childSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(childRefs[child.id]!), source: 'location_write_service.get');
        if (!childSnapshot.exists) {
          throw StateError('수정할 자식 구역이 없습니다: ${child.id}');
        }
        final storedParentId =
            (childSnapshot.data()?['parentId'] ?? '').toString().trim();
        if (storedParentId.isNotEmpty && storedParentId != parent.id) {
          throw StateError('자식 구역의 부모는 변경할 수 없습니다: ${child.id}');
        }
        previousSlotIdsByChild[child.id] =
            _slotIdsFromData(childSnapshot.data());
      }

      final reservationSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final areaId in nextOwnerByAreaId.keys) {
        reservationSnapshots[areaId] =
            await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(_reservationRef(parent.id, areaId)), source: 'location_write_service.get');
      }

      for (final entry in reservationSnapshots.entries) {
        if (!entry.value.exists) continue;
        final expectedOwner = nextOwnerByAreaId[entry.key]!;
        final storedOwner =
            (entry.value.data()?['childId'] ?? '').toString().trim();
        if (storedOwner.isEmpty || storedOwner == expectedOwner) continue;
        final storedOwnerNextIds = nextIdsByChild[storedOwner];
        final releasedInThisTransaction = storedOwnerNextIds != null &&
            !storedOwnerNextIds.contains(entry.key);
        if (!releasedInThisTransaction) {
          throw StateError('이미 사용 중인 주차면입니다: ${entry.key}');
        }
      }

      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => transaction.update(parentRef, parentData));

      final childById = <String, LocationModel>{
        for (final child in children) child.id: child,
      };
      final previousAreaIds = <String>{};

      for (final child in children) {
        previousAreaIds.addAll(
          previousSlotIdsByChild[child.id] ?? <String>{},
        );
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => transaction.update(childRefs[child.id]!, _compositeChildData(child)));
      }

      for (final areaId
          in previousAreaIds.difference(nextOwnerByAreaId.keys.toSet())) {
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => transaction.delete(_reservationRef(parent.id, areaId)));
      }
      for (final entry in nextOwnerByAreaId.entries) {
        final child = childById[entry.value]!;
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => transaction.set(
          _reservationRef(parent.id, entry.key),
          _reservationData(parent: parent, child: child, areaId: entry.key),
        ));
      }
    }), source: 'location_write_service.runTransaction');

    debugPrint(
      'updateCompositeParentWithChildren parent=${parent.id} children=${children.length}',
    );
  }

  Future<void> createCompositeChild({
    required LocationModel parent,
    required LocationModel child,
  }) async {
    if (!_isCompositeParent(parent)) {
      throw ArgumentError('parent must be type=composite_parent');
    }
    if (!_isCompositeChild(child)) {
      throw ArgumentError('child must be type=composite_child');
    }
    if ((child.parentId ?? '').trim() != parent.id) {
      throw ArgumentError('child parentId does not match parent id');
    }
    if (child.companyId != parent.companyId || child.area != parent.area) {
      throw StateError('LOCATION_PARENT_CHILD_SCOPE_MISMATCH');
    }

    final childData = _compositeChildData(child);
    final parentRef = _firestore.collection('locations').doc(parent.id);
    final childRef = _firestore.collection('locations').doc(child.id);
    final slotIds = _slotIds(child);
    final reservationRefs = <String, DocumentReference<Map<String, dynamic>>>{
      for (final areaId in slotIds) areaId: _reservationRef(parent.id, areaId),
    };

    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((transaction) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      final parentSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(parentRef), source: 'location_write_service.get');
      final childSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(childRef), source: 'location_write_service.get');
      final reservationSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in reservationRefs.entries) {
        reservationSnapshots[entry.key] = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(entry.value), source: 'location_write_service.get');
      }

      if (!parentSnapshot.exists ||
          (parentSnapshot.data()?['type'] ?? '').toString() !=
              'composite_parent') {
        throw StateError('부모 구역이 존재하지 않습니다.');
      }
      if (childSnapshot.exists) {
        throw StateError('이미 존재하는 자식 구역입니다.');
      }
      for (final entry in reservationSnapshots.entries) {
        if (entry.value.exists) {
          throw StateError('이미 사용 중인 주차면입니다: ${entry.key}');
        }
      }

      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => transaction.set(childRef, childData, SetOptions(merge: true)));
      for (final areaId in slotIds) {
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => transaction.set(
          reservationRefs[areaId]!,
          _reservationData(parent: parent, child: child, areaId: areaId),
        ));
      }
    }), source: 'location_write_service.runTransaction');

    debugPrint(
      'createCompositeChild id=${child.id} parentId=${parent.id} slots=${slotIds.length}',
    );
  }

  Future<void> updateCompositeChild({
    required LocationModel parent,
    required LocationModel previous,
    required LocationModel updated,
  }) async {
    if (!_isCompositeParent(parent)) {
      throw ArgumentError('parent must be type=composite_parent');
    }
    if (!_isCompositeChild(previous) || !_isCompositeChild(updated)) {
      throw ArgumentError('previous and updated must be composite_child');
    }
    if (previous.id != updated.id) {
      throw ArgumentError('child id cannot be changed');
    }
    if ((updated.parentId ?? '').trim() != parent.id) {
      throw ArgumentError('updated child parentId does not match parent id');
    }
    if (updated.companyId != parent.companyId || updated.area != parent.area ||
        previous.companyId != parent.companyId) {
      throw StateError('LOCATION_PARENT_CHILD_SCOPE_MISMATCH');
    }

    final parentRef = _firestore.collection('locations').doc(parent.id);
    final childRef = _firestore.collection('locations').doc(updated.id);
    final nextIds = _slotIds(updated);

    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((transaction) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      final parentSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(parentRef), source: 'location_write_service.get');
      final childSnapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(childRef), source: 'location_write_service.get');
      final reservationSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final areaId in nextIds) {
        reservationSnapshots[areaId] =
            await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(_reservationRef(parent.id, areaId)), source: 'location_write_service.get');
      }

      if (!parentSnapshot.exists ||
          (parentSnapshot.data()?['type'] ?? '').toString() !=
              'composite_parent') {
        throw StateError('부모 구역이 존재하지 않습니다.');
      }
      if (!childSnapshot.exists) {
        throw StateError('수정할 자식 구역이 없습니다.');
      }

      final storedParentId =
          (childSnapshot.data()?['parentId'] ?? '').toString().trim();
      if (storedParentId.isNotEmpty && storedParentId != parent.id) {
        throw StateError('자식 구역의 부모는 변경할 수 없습니다.');
      }

      for (final entry in reservationSnapshots.entries) {
        if (!entry.value.exists) continue;
        final ownerId =
            (entry.value.data()?['childId'] ?? '').toString().trim();
        if (ownerId.isNotEmpty && ownerId != updated.id) {
          throw StateError('이미 사용 중인 주차면입니다: ${entry.key}');
        }
      }

      final storedPreviousIds = _slotIdsFromData(childSnapshot.data());
      final removedIds = storedPreviousIds.difference(nextIds);

      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => transaction.update(childRef, _compositeChildData(updated)));
      for (final areaId in removedIds) {
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.delete, () => transaction.delete(_reservationRef(parent.id, areaId)));
      }
      for (final areaId in nextIds) {
        FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.set, () => transaction.set(
          _reservationRef(parent.id, areaId),
          _reservationData(parent: parent, child: updated, areaId: areaId),
        ));
      }
    }), source: 'location_write_service.runTransaction');

    debugPrint(
      'updateCompositeChild id=${updated.id} parentId=${parent.id} slots=${nextIds.length}',
    );
  }

  Future<void> updatePlainTextLocation(LocationModel location) async {
    final locationName = location.locationName.trim();
    if (locationName.isEmpty) {
      throw ArgumentError('plain text locationName cannot be empty');
    }
    if ((location.type ?? 'single') != 'single') {
      throw ArgumentError('updatePlainTextLocation requires type=single');
    }
    if (location.capacity < 0 || location.capacity > 9999) {
      throw ArgumentError('plain text capacity must be between 0 and 9999');
    }

    final ref = _firestore.collection('locations').doc(location.id);
    if (location.companyId.trim().isEmpty) {
      throw StateError('LOCATION_COMPANY_ID_REQUIRED');
    }
    final data = location.toFirestoreMap();
    data['type'] = 'single';
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['parentId'] = FieldValue.delete();
    data['parent'] = FieldValue.delete();
    data['parkingGrid'] = FieldValue.delete();
    data['childRect'] = FieldValue.delete();
    data['childKind'] = FieldValue.delete();
    data['childSlotAreaIds'] = FieldValue.delete();
    data['childSlots'] = FieldValue.delete();

    await FirebaseActivityMonitor.track(FirebaseActivityKind.transaction, () => _firestore.runTransaction((transaction) async {
        FirebaseActivityMonitor.beginTransactionAttempt();
      final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => transaction.get(ref), source: 'location_write_service.get');
      if (!snapshot.exists) {
        throw StateError('수정할 텍스트 구역이 없습니다.');
      }
      FirebaseActivityMonitor.transactionCommand(FirebaseActivityDocumentCommand.update, () => transaction.update(ref, data));
    }), source: 'location_write_service.runTransaction');
    debugPrint(
      'updatePlainTextLocation id=${location.id} area=${location.area} name=$locationName',
    );
  }

  Future<void> deleteLocations({
    required String area,
    required List<String> ids,
    List<({String parentId, ParkingGridModel parkingGrid})> parentGridUpdates =
        const [],
    List<LocationSlotReservationKey> slotReservationDeletes = const [],
  }) async {
    if (ids.isEmpty &&
        parentGridUpdates.isEmpty &&
        slotReservationDeletes.isEmpty) {
      return;
    }

    final batch = _firestore.batch();
    try {

    for (final update in parentGridUpdates) {
      final ref = _firestore.collection('locations').doc(update.parentId);
      FirebaseActivityWriteScope.batchCommand(batch, FirebaseActivityDocumentCommand.update, () => batch.update(ref, <String, dynamic>{
        'parkingGrid': update.parkingGrid.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      }));
    }

    for (final key in slotReservationDeletes) {
      FirebaseActivityWriteScope.batchCommand(batch, FirebaseActivityDocumentCommand.delete, () => batch.delete(_reservationRef(key.parentId, key.areaId)));
    }

    for (final id in ids) {
      FirebaseActivityWriteScope.batchCommand(batch, FirebaseActivityDocumentCommand.delete, () => batch.delete(_firestore.collection('locations').doc(id)));
    }

    await FirebaseActivityMonitor.track(FirebaseActivityKind.batch, () => batch.commit(), batch: batch, source: 'location_write_service.commit');
    } finally {
      FirebaseActivityWriteScope.cancelBatch(batch);
    }
    debugPrint(
      'deleteLocations area=$area ids=${ids.length} reservations=${slotReservationDeletes.length}',
    );
  }
}
