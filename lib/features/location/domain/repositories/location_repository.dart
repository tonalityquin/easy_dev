import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../models/location_model.dart';
import '../models/parking_grid_model.dart';

abstract class LocationRepository {
  Future<List<LocationModel>> getLocationsOnce(String area);

  Future<void> addCompositeParent(LocationModel parent);

  Future<void> addCompositeChild(LocationModel child);

  Future<void> addPlainTextLocation(LocationModel location);

  Future<void> addCompositeChildWithParentGridUpdate({
    required LocationModel parent,
    required LocationModel child,
  });

  Future<void> saveCompositeParentWithChildren({
    required LocationModel parent,
    required List<LocationModel> children,
  });

  Future<void> deleteLocations({
    required String area,
    required List<String> ids,
    List<({String parentId, ParkingGridModel parkingGrid})> parentGridUpdates =
    const [],
  });

  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = PlateTypeFirestoreValue.parkingCompleted,
  });
}
