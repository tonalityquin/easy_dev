import '../../models/location_model.dart';

abstract class LocationRepository {
  Future<List<LocationModel>> getLocationsOnce(String area);

  Future<void> addSingleLocation(LocationModel location);

  Future<void> deleteLocations(List<String> ids);

  Future<void> addCompositeLocation(
      String parent,
      List<Map<String, dynamic>> subs,
      String area,
      );

  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
  });
}
