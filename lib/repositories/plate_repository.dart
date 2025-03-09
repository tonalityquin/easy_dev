import '../models/plate_model.dart';

/// 직접 인스턴스를 만들 수 없는 추상 클래스
abstract class PlateRepository {
  Stream<List<PlateModel>> getCollectionStream(
      String collectionName); // collectionName의 모든 문서를 Stream(데이터가 변경될 때마다 UI 업데이트)으로 가져온다.
  Future<void> addOrUpdateDocument(String collection, String documentId,
      Map<String, dynamic> data); // collection과 documentId로 문서를 찾는다, data(Map<String, dynamic>)는 Firestore에 저장할 데이터이다.

  Future<void> deleteDocument(String collection, String documentId); // collection과 documentId로 문서를 찾는다.

  Future<PlateModel?> getDocument(String collection, String documentId); // collection과 documentId로 문서를 찾는다.

  Future<void> deleteAllData();

  Future<void> togglePlateSelection(String collection, String id, bool isSelected,
      {String? whoSelected}); // collection과 documentId, isSelected 선택 여부로 문서를 찾는다.

  /// 특정 지역의 사용 가능한 위치 목록을 가져온다.
  Future<List<String>> getAvailableLocations(String area); // area로 문서를 찾는다.

  /// Firestore에 "요청" 또는 "완료 데이터를 추가하는 메서드
  Future<void> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
    required String userName,
    String? adjustmentType,
    List<String>? memoList,
    int basicStandard,
    int basicAmount,
    int addStandard,
    int addAmount,
  });
}
