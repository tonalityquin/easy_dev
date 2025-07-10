import '../../models/location_model.dart';

abstract class LocationRepository {

  /// 특정 지역의 모든 위치 정보 조회 (단발성)
  Future<List<LocationModel>> getLocationsOnce(String area);

  /// 단일 위치 추가
  Future<void> addSingleLocation(LocationModel location);

  /// 여러 위치 삭제
  Future<void> deleteLocations(List<String> ids);

  /// 복합 주차 구역 추가 (하위 구역 이름과 용량 정보 포함)
  Future<void> addCompositeLocation(
      String parent,
      List<Map<String, dynamic>> subs, // [{name: 'B1', capacity: 10}, ...]
      String area,
      );

  /// ✅ 추가: plates 컬렉션에서 단일 위치의 입차 수 조회
  Future<int> getPlateCount({
    required String locationName,
    required String area,
    String type = 'parking_completed',
  });

  /// ✅ 추가: 복수 위치의 입차 수 일괄 조회 (composite 하위 구역용)
  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
  });
}
