import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/location_model.dart';
import '../../domain/models/parking_grid_model.dart';

class LocationWriteService {
  final FirebaseFirestore _firestore;

  LocationWriteService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  bool _isCompositeParent(LocationModel loc) =>
      (loc.type ?? '') == 'composite_parent';

  bool _isCompositeChild(LocationModel loc) {
    final t = loc.type ?? 'single';
    return t == 'composite_child' || t == 'composite';
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

    int idx(int r, int c) => r * cols + c;
    final used = <int>{};
    final ids = <String>{};

    for (final a in areas) {
      final id = a.id.trim();
      if (id.isEmpty) {
        throw ArgumentError('parkingArea id cannot be empty');
      }
      if (!ids.add(id)) {
        throw ArgumentError('duplicate parkingArea id: $id');
      }

      final r0 = a.r0;
      final c0 = a.c0;
      final r1 = a.r1;
      final c1 = a.c1;

      if (r0 < 0 || c0 < 0 || r1 < 0 || c1 < 0) {
        throw ArgumentError('parkingArea has negative index: $id');
      }
      if (r0 >= rows || r1 >= rows || c0 >= cols || c1 >= cols) {
        throw ArgumentError('parkingArea out of bounds: $id');
      }

      final top = r0 < r1 ? r0 : r1;
      final bottom = r0 < r1 ? r1 : r0;
      final left = c0 < c1 ? c0 : c1;
      final right = c0 < c1 ? c1 : c0;

      for (int r = top; r <= bottom; r++) {
        for (int c = left; c <= right; c++) {
          final p = idx(r, c);
          if (used.contains(p)) {
            throw ArgumentError('parkingAreas overlap (id=$id, cell=$r,$c)');
          }
          if (grid.cells[p] != ParkingGridCellType.empty) {
            throw ArgumentError(
              'parkingArea must be on EMPTY cells only (id=$id, cell=$r,$c)',
            );
          }
          used.add(p);
        }
      }
    }
  }

  Future<void> addCompositeParent(LocationModel parent) async {
    if (!_isCompositeParent(parent)) {
      throw ArgumentError('addCompositeParent requires type=composite_parent');
    }

    final parentName = parent.locationName.trim();
    if (parentName.isEmpty) {
      throw ArgumentError('parent locationName cannot be empty');
    }

    final grid = parent.parkingGrid;
    if (grid == null) {
      throw ArgumentError('composite_parent requires non-null parkingGrid');
    }

    _validateParkingGrid(grid);

    final ref = _firestore.collection('locations').doc(parent.id);

    final data = parent.toFirestoreMap();
    data['type'] = 'composite_parent';
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['parkingGrid'] = grid.toJson();

    if (kDebugMode) {
      debugPrint(
        '🧩 addCompositeParent: id=${parent.id}, area=${parent.area}, '
            'name="$parentName", grid=${grid.rows}x${grid.cols}, '
            'parkingAreas=${grid.parkingAreas.length}',
      );
    }

    await ref.set(data, SetOptions(merge: true));
  }


  Future<void> addPlainTextLocation(LocationModel location) async {
    final locationName = location.locationName.trim();
    if (locationName.isEmpty) {
      throw ArgumentError('plain text locationName cannot be empty');
    }
    if ((location.type ?? 'single') != 'single') {
      throw ArgumentError('addPlainTextLocation requires type=single');
    }

    final ref = _firestore.collection('locations').doc(location.id);

    final data = location.toFirestoreMap();
    data['type'] = 'single';
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['parkingGrid'] = FieldValue.delete();
    data['childRect'] = FieldValue.delete();
    data['childKind'] = FieldValue.delete();
    data['childSlots'] = FieldValue.delete();

    if (kDebugMode) {
      debugPrint(
        '🧩 addPlainTextLocation: id=${location.id}, area=${location.area}, '
            'name="$locationName", cap=${location.capacity}',
      );
    }

    await ref.set(data, SetOptions(merge: true));
  }
  Future<void> addCompositeChild(LocationModel child) async {
    if (!_isCompositeChild(child)) {
      throw ArgumentError(
        'addCompositeChild requires type=composite_child (or legacy composite)',
      );
    }

    final childName = child.locationName.trim();
    if (childName.isEmpty) {
      throw ArgumentError('child locationName cannot be empty');
    }

    final parentName = (child.parent ?? '').trim();
    if (parentName.isEmpty) {
      throw ArgumentError('composite_child must have non-empty parent');
    }

    if (child.childRect == null) {
      throw ArgumentError('composite_child must have non-null childRect');
    }

    final ref = _firestore.collection('locations').doc(child.id);

    final data = child.toFirestoreMap();
    data['type'] = 'composite_child';
    data['updatedAt'] = FieldValue.serverTimestamp();
    data.remove('parkingGrid');

    if (kDebugMode) {
      debugPrint(
        '🧩 addCompositeChild: id=${child.id}, area=${child.area}, '
            'parent="$parentName", child="$childName", cap=${child.capacity}, '
            'childSlots=${child.childSlots.length}',
      );
    }

    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> addCompositeChildWithParentGridUpdate({
    required LocationModel parent,
    required LocationModel child,
  }) async {
    if (!_isCompositeParent(parent)) {
      throw ArgumentError('parent must be type=composite_parent');
    }
    if (!_isCompositeChild(child)) {
      throw ArgumentError('child must be type=composite_child');
    }

    final parentGrid = parent.parkingGrid;
    if (parentGrid == null) {
      throw ArgumentError('parent parkingGrid cannot be null');
    }

    _validateParkingGrid(parentGrid);

    final childData = child.toFirestoreMap()
      ..['type'] = 'composite_child'
      ..['updatedAt'] = FieldValue.serverTimestamp();
    childData.remove('parkingGrid');

    final parentData = parent.toFirestoreMap()
      ..['type'] = 'composite_parent'
      ..['updatedAt'] = FieldValue.serverTimestamp()
      ..['parkingGrid'] = parentGrid.toJson();

    final batch = _firestore.batch();

    final parentRef = _firestore.collection('locations').doc(parent.id);
    final childRef = _firestore.collection('locations').doc(child.id);

    batch.set(parentRef, parentData, SetOptions(merge: true));
    batch.set(childRef, childData, SetOptions(merge: true));

    if (kDebugMode) {
      debugPrint(
        '🧩 addCompositeChildWithParentGridUpdate: parent=${parent.id}, child=${child.id}, '
            'areas=${parentGrid.parkingAreas.length}',
      );
    }

    await batch.commit();
  }

  Future<void> deleteLocations({
    required String area,
    required List<String> ids,
    List<({String parentId, ParkingGridModel parkingGrid})> parentGridUpdates =
    const [],
  }) async {
    if (ids.isEmpty && parentGridUpdates.isEmpty) return;

    final batch = _firestore.batch();

    for (final u in parentGridUpdates) {
      final ref = _firestore.collection('locations').doc(u.parentId);
      batch.set(
        ref,
        <String, dynamic>{
          'parkingGrid': u.parkingGrid.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    for (final id in ids) {
      final docRef = _firestore.collection('locations').doc(id);
      batch.delete(docRef);
    }

    await batch.commit();
  }
}
