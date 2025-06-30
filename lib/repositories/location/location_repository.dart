import '../../models/location_model.dart';

abstract class LocationRepository {

  Future<List<LocationModel>> getLocationsOnce(String area);

  Future<void> addSingleLocation(LocationModel location);

  Future<void> deleteLocations(List<String> ids);


  /// ✅ 수정: 하위 구역 이름과 용량 정보 포함
  Future<void> addCompositeLocation(
      String parent,
      List<Map<String, dynamic>> subs, // [{name: 'B1', capacity: 10}, ...]
      String area,
      );
}
