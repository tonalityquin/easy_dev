import '../../models/location_model.dart';

abstract class LocationRepository {
  Stream<List<LocationModel>> getLocationsStream(String area);

  Future<List<LocationModel>> getLocationsOnce(String area);

  Future<void> addLocation(LocationModel location);

  Future<void> deleteLocations(List<String> ids);

  Future<void> toggleLocationSelection(String id, bool isSelected);

  /// ✅ 수정: 하위 구역 이름과 용량 정보 포함
  Future<void> addCompositeLocation(
      String parent,
      List<Map<String, dynamic>> subs, // [{name: 'B1', capacity: 10}, ...]
      String area,
      );
}
