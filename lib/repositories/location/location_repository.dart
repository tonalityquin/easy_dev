import '../../models/location_model.dart';

abstract class LocationRepository {
  Stream<List<LocationModel>> getLocationsStream();
  Future<void> addLocation(LocationModel location);
  Future<void> deleteLocations(List<String> ids);
  Future<void> toggleLocationSelection(String id, bool isSelected);
}
