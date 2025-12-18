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

  /// 기본: 동일 area로 묶어 집계
  /// - locationCounts 캐시(areas/{area}/locationCounts/{type})는 더 이상 사용하지 않음
  /// - 항상 Firestore aggregation count() 기반으로 집계 결과를 반환
  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
  });
}
