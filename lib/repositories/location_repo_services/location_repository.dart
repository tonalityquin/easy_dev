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
  /// - bypassCache=true일 때는 캐시를 무시하고 Firestore count()를 강제 수행
  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
    bool bypassCache = false, // ⬅⬅⬅ 인터페이스에도 기본값 명시
  });
}
