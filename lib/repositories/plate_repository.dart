import '../models/plate_model.dart';

/// Plate 관련 데이터를 처리하는 추상 클래스
abstract class PlateRepository {
  /// Firestore 컬렉션을 스트림 형태로 가져온다.
  Stream<List<PlateModel>> getCollectionStream(String collectionName);

  /// 문서를 추가하거나 업데이트한다.
  Future<void> addOrUpdateDocument(String collection, String documentId, Map<String, dynamic> data);

  /// 특정 문서를 삭제한다.
  Future<void> deleteDocument(String collection, String documentId);

  /// 특정 문서를 가져온다.
  Future<PlateModel?> getDocument(String collection, String documentId);

  /// Firestore 내 모든 Plate 데이터를 삭제한다.
  Future<void> deleteAllData();

  /// Plate 선택 상태를 업데이트한다.
  Future<void> updatePlateSelection(String collection, String id, bool isSelected, {String? selectedBy});

  /// 요청 데이터를 Firestore에 추가하거나 완료 데이터로 업데이트한다.
  Future<void> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
    required String userName,
    String? adjustmentType,
    List<String>? statusList,
    int basicStandard,
    int basicAmount,
    int addStandard,
    int addAmount,
  });

  /// 특정 지역의 사용 가능한 위치 목록을 가져온다.
  Future<List<String>> getAvailableLocations(String area);
}
