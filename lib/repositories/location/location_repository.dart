import '../../models/location_model.dart';

/// 위치 관련 Firestore 데이터 접근을 정의한 추상 클래스
abstract class LocationRepository {
  /// 🔁 실시간 위치 스트림
  Stream<List<LocationModel>> getLocationsStream(String area);

  /// ✅ 단발성 위치 조회 (.get() 기반)
  Future<List<LocationModel>> getLocationsOnce(String area);

  /// 위치 추가
  Future<void> addLocation(LocationModel location);

  /// 여러 위치 삭제
  Future<void> deleteLocations(List<String> ids);

  /// 선택 여부 토글
  Future<void> toggleLocationSelection(String id, bool isSelected);

  /// 복합 위치 추가
  Future<void> addCompositeLocation(String parent, List<String> subs, String area);
}
