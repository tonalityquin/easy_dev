import '../../models/location_model.dart';
import 'location_repository.dart';
import 'location_read_service.dart';
import 'location_write_service.dart';
import 'location_count_service.dart';

class FirestoreLocationRepository implements LocationRepository {
  final LocationReadService _readService = LocationReadService();
  final LocationWriteService _writeService = LocationWriteService();
  final LocationCountService _countService = LocationCountService();

  @override
  Future<List<LocationModel>> getLocationsOnce(String area) {
    return _readService.getLocationsOnce(area);
  }

  @override
  Future<void> addSingleLocation(LocationModel location) {
    return _writeService.addSingleLocation(location);
  }

  @override
  Future<void> deleteLocations(List<String> ids) {
    return _writeService.deleteLocations(ids);
  }

  @override
  Future<void> addCompositeLocation(
      String parent,
      List<Map<String, dynamic>> subs,
      String area,
      ) {
    return _writeService.addCompositeLocation(parent, subs, area);
  }

  @override
  Future<int> getPlateCount({
    required String locationName,
    required String area,
    String type = 'parking_completed',
  }) {
    return _countService.getPlateCount(
      locationName: locationName,
      area: area,
      type: type,
    );
  }

  @override
  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
  }) {
    return _countService.getPlateCountsForLocations(
      locationNames: locationNames,
      area: area,
      type: type,
    );
  }
}
