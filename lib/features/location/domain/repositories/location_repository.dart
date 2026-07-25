import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../models/location_model.dart';
import '../models/parking_grid_model.dart';

typedef LocationSlotReservationKey = ({String parentId, String areaId});

abstract class LocationRepository {
  Future<List<LocationModel>> getLocationsOnce(String area);

  Future<void> createCompositeParent(LocationModel parent);

  Future<void> updateCompositeParentWithChildren({
    required LocationModel parent,
    required List<LocationModel> children,
  });

  Future<void> createCompositeChild({
    required LocationModel parent,
    required LocationModel child,
  });

  Future<void> updateCompositeChild({
    required LocationModel parent,
    required LocationModel previous,
    required LocationModel updated,
  });

  Future<void> updatePlainTextLocation(LocationModel location);

  Future<void> deleteLocations({
    required String area,
    required List<String> ids,
    List<({String parentId, ParkingGridModel parkingGrid})> parentGridUpdates =
        const [],
    List<LocationSlotReservationKey> slotReservationDeletes = const [],
  });

  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = PlateTypeFirestoreValue.parkingCompleted,
  });
}
