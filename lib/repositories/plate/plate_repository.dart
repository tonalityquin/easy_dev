import '../../models/plate_model.dart';

abstract class PlateRepository {
  Stream<List<PlateModel>> getCollectionStream(String collectionName);

  Future<void> addOrUpdateDocument(String collection, String documentId, Map<String, dynamic> data);

  Future<void> deleteDocument(String collection, String documentId);

  Future<PlateModel?> getDocument(String collection, String documentId);

  Future<List<PlateModel>> getPlatesByArea(String collection, String area);

  Future<void> deleteAllData();

  Future<void> updatePlateSelection(String collection, String id, bool isSelected, {String? selectedBy});

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
    required String region,
    List<String>? imageUrls,
    bool isLockedFee, // ✅ 사전 정산 여부
    int? lockedAtTimeInSeconds, // ✅ 정산 시각 (초 단위)
  });


  Future<List<String>> getAvailableLocations(String area);
}
