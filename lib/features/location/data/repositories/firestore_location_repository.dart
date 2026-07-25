import 'package:flutter/foundation.dart';

import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../domain/models/location_model.dart';
import '../../domain/models/parking_grid_model.dart';
import '../../domain/repositories/location_repository.dart';
import '../services/location_count_service.dart';
import '../services/location_read_service.dart';
import '../services/location_write_service.dart';

class FirestoreLocationRepository implements LocationRepository {
  final LocationReadService _readService;
  final LocationWriteService _writeService;
  final LocationCountService _countService;

  FirestoreLocationRepository({
    LocationReadService? readService,
    LocationWriteService? writeService,
    LocationCountService? countService,
  })  : _readService = readService ?? LocationReadService(),
        _writeService = writeService ?? LocationWriteService(),
        _countService = countService ?? LocationCountService();

  @override
  Future<List<LocationModel>> getLocationsOnce(String area) {
    return _readService.getLocationsOnce(area);
  }

  @override
  Future<void> createCompositeParent(LocationModel parent) {
    return _writeService.createCompositeParent(parent);
  }

  @override
  Future<void> updateCompositeParentWithChildren({
    required LocationModel parent,
    required List<LocationModel> children,
  }) {
    return _writeService.updateCompositeParentWithChildren(
      parent: parent,
      children: children,
    );
  }

  @override
  Future<void> createCompositeChild({
    required LocationModel parent,
    required LocationModel child,
  }) {
    return _writeService.createCompositeChild(
      parent: parent,
      child: child,
    );
  }

  @override
  Future<void> updateCompositeChild({
    required LocationModel parent,
    required LocationModel previous,
    required LocationModel updated,
  }) {
    return _writeService.updateCompositeChild(
      parent: parent,
      previous: previous,
      updated: updated,
    );
  }

  @override
  Future<void> updatePlainTextLocation(LocationModel location) {
    return _writeService.updatePlainTextLocation(location);
  }

  @override
  Future<void> deleteLocations({
    required String area,
    required List<String> ids,
    List<({String parentId, ParkingGridModel parkingGrid})> parentGridUpdates =
        const [],
    List<LocationSlotReservationKey> slotReservationDeletes = const [],
  }) {
    return _writeService.deleteLocations(
      area: area,
      ids: ids,
      parentGridUpdates: parentGridUpdates,
      slotReservationDeletes: slotReservationDeletes,
    );
  }

  @override
  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = PlateTypeFirestoreValue.parkingCompleted,
  }) async {
    final requested = locationNames.toSet().toList();
    debugPrint(
      '📌 plateCount 집계: count() 수행: ${requested.length}개 (area=$area, type=$type)',
    );

    return _countService.getPlateCountsForLocations(
      locationNames: requested,
      area: area,
      type: type,
    );
  }
}
