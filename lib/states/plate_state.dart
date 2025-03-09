import 'package:flutter/material.dart';
import '../repositories/plate_repository.dart';
import '../models/plate_model.dart';

class PlateState extends ChangeNotifier {
  final PlateRepository _repository;

  PlateState(this._repository) {
    _initializeSubscriptions();
  }

  final Map<String, List<PlateModel>> _data = {
    'parking_requests': [],
    'parking_completed': [],
    'departure_requests': [],
    'departure_completed': [],
  };

  String? _searchQuery; // ✅ 검색어 저장 변수 추가

  /// 🔹 검색어 Getter 추가
  String get searchQuery => _searchQuery ?? "";

  /// 🔹 검색어 설정 (`filterByLastFourDigits()` → `setSearchQuery()`로 변경)
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// 🔹 검색 초기화
  void clearPlateSearchQuery() {
    _searchQuery = null;
    notifyListeners();
  }

  /// 🔹 특정 지역의 번호판 리스트 반환 (검색 기능 추가)
  List<PlateModel> getPlatesByArea(String collection, String area) {
    final plates = _data[collection]?.where((request) => request.area == area).toList() ?? [];

    // 🔍 검색어 필터링 적용
    if (_searchQuery != null && _searchQuery!.length == 4) {
      return plates.where((plate) {
        final last4Digits = plate.plateNumber.length >= 4
            ? plate.plateNumber.substring(plate.plateNumber.length - 4)
            : plate.plateNumber;
        return last4Digits == _searchQuery;
      }).toList();
    }

    return plates;
  }

  /// 🔹 Firestore 실시간 데이터 동기화 초기화
  void _initializeSubscriptions() {
    for (final collectionName in _data.keys) {
      _repository.getCollectionStream(collectionName).listen((data) {
        _data[collectionName] = data;
        notifyListeners();
      });
    }
  }

  /// 🔹 특정 지역의 번호판 중 사용자가 입력한 4자리와 일치하는 번호판 필터링
  List<PlateModel> getFilteredPlates(String collection, String area, String? searchDigits) {
    final plates = getPlatesByArea(collection, area); // 기존 지역 필터링된 리스트 가져오기

    if (searchDigits == null || searchDigits.isEmpty) {
      return plates; // 검색어가 없으면 전체 리스트 반환
    }

    return plates.where((plate) {
      // 🔹 번호판의 마지막 4자리를 추출
      final last4Digits =
          plate.plateNumber.length >= 4 ? plate.plateNumber.substring(plate.plateNumber.length - 4) : plate.plateNumber;

      return last4Digits == searchDigits; // 입력한 4자리와 비교하여 필터링
    }).toList();
  }

  /// 🔹 특정 주차 구역의 plate_container만 필터링 (번호판 검색과 동일한 방식 적용)
  List<PlateModel> filterByParkingArea(String collection, String area, String parkingLocation) {
    debugPrint("🚀 filterByParkingArea() 호출됨: 지역 = $area, 주차 구역 = $parkingLocation");

    // 🔹 1. 먼저 해당 지역(area)에 속하는 plate 목록을 가져옴 (번호판 검색과 동일)
    List<PlateModel> plates = _data[collection]?.where((plate) => plate.area == area).toList() ?? [];

    debugPrint("📌 지역 필터링 후 plate 개수: ${plates.length}");

    // 🔹 2. 선택한 주차 구역(location)에 맞게 추가 필터링
    plates = plates.where((plate) => plate.location == parkingLocation).toList();

    debugPrint("📌 주차 구역 필터링 후 plate 개수: ${plates.length}");

    return plates; // ✅ _data를 변경하지 않고 필터링된 리스트 반환
  }

  /// 🔹 주차 구역 검색 초기화 (번호판 검색 초기화 방식과 동일하게 구현)
  void clearLocationSearchQuery() {
    debugPrint("🔄 주차 구역 검색 초기화 호출됨");
    _initializeSubscriptions(); // ✅ Firestore의 원본 데이터를 다시 가져옴
    notifyListeners();
  }

  /// 번호판 중복 여부 확인
  bool isPlateNumberDuplicated(String plateNumber, String area) {
    final platesInArea = _data.entries
        .where((entry) => entry.key != 'departure_completed') // 'departure_completed' 제외
        .expand((entry) => entry.value) // 각 컬렉션 데이터 평탄화
        .where((request) => request.area == area) // 특정 지역 데이터 필터링
        .map((request) => request.plateNumber); // 번호판만 추출
    return platesInArea.contains(plateNumber); // 중복 여부 확인
  }

  /// 번호판 추가 요청 처리
  Future<bool> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
    required String userName,
    String? whoSelected,
    String? adjustmentType,
    List<String>? statusList,
  }) async {
    final documentId = '${plateNumber}_$area';

    try {
      int basicStandard = 0;
      int basicAmount = 0;
      int addStandard = 0;
      int addAmount = 0;

      if (adjustmentType != null) {
        final adjustmentData = await _repository.getDocument('adjustments', adjustmentType);
        if (adjustmentData != null) {
          basicStandard = adjustmentData.basicStandard ?? 0;
          basicAmount = adjustmentData.basicAmount ?? 0;
          addStandard = adjustmentData.addStandard ?? 0;
          addAmount = adjustmentData.addAmount ?? 0;
        } else {
          debugPrint('⚠ Firestore에서 adjustmentType=$adjustmentType 데이터를 찾을 수 없음');
        }
      }

      await _repository.addOrUpdateDocument(collection, documentId, {
        'plate_number': plateNumber,
        'type': type,
        'request_time': DateTime.now(),
        'location': location.isNotEmpty ? location : '미지정',
        'area': area,
        'user_name': userName,
        'adjustment_type': adjustmentType,
        'memo_list': statusList ?? [],
        'isSelected': false,
        'who_selected': whoSelected,
        'basic_standard': basicStandard,
        'basic_amount': basicAmount,
        'add_standard': addStandard,
        'add_amount': addAmount,
      });

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Error adding request: $e');
      return false;
    }
  }

  /// 데이터 전송 처리
  Future<bool> transferData({
    required String fromCollection,
    required String toCollection,
    required String plateNumber,
    required String area,
    required String newType,
  }) async {
    final documentId = '${plateNumber}_$area';

    try {
      final documentData = await _repository.getDocument(fromCollection, documentId);

      if (documentData != null) {
        await _repository.deleteDocument(fromCollection, documentId);

        // ✅ 입차 요청 상태로 변경될 경우만 "미지정"으로 설정
        final updatedLocation = (toCollection == 'parking_requests') ? "미지정" : documentData.location;

        await _repository.addOrUpdateDocument(toCollection, documentId, {
          ...documentData.toMap(),
          'type': newType,
          'location': updatedLocation, // ✅ 주차 구역 유지 또는 "미지정"
          'isSelected': false,
          'who_selected': null,
        });

        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error transferring data: $e');
      return false;
    }
  }

  /// 🔹 선택 상태 토글 (`copyWith()` 제거)
  Future<void> toggleIsSelected({
    required String collection,
    required String plateNumber,
    required String area,
    required String userName,
    required void Function(String) onError, // ✅ UI에서 Snackbar 실행하도록 수정
  }) async {
    final plateId = '${plateNumber}_$area';

    try {
      final plateList = _data[collection];
      if (plateList == null) throw Exception('🚨 Collection not found');

      final index = plateList.indexWhere((p) => p.id == plateId);
      if (index == -1) throw Exception('🚨 Plate not found');

      final plate = plateList[index];

      final newIsSelected = !plate.isSelected;
      final newWhoSelected = newIsSelected ? userName : null;

      await _repository.togglePlateSelection(
        collection,
        plateId,
        newIsSelected,
        whoSelected: newWhoSelected,
      );

      _data[collection]![index] = PlateModel(
        id: plate.id,
        plateNumber: plate.plateNumber,
        type: plate.type,
        entryTime: plate.entryTime,
        location: plate.location,
        area: plate.area,
        userName: plate.userName,
        isSelected: newIsSelected,
        whoSelected: newWhoSelected,
        adjustmentType: plate.adjustmentType,
        memoList: plate.memoList,
        basicStandard: plate.basicStandard,
        basicAmount: plate.basicAmount,
        addStandard: plate.addStandard,
        addAmount: plate.addAmount,
      );

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error toggling isSelected: $e');

      // ✅ `onError` 콜백을 호출하여 UI에서 Snackbar 실행
      onError('🚨 번호판 선택 상태 변경 실패: $e');
    }
  }

  /// 🔹 선택된 번호판 반환
  PlateModel? getSelectedPlate(String collection, String userName) {
    final plates = _data[collection];

    // 컬렉션이 비어 있다면 null 반환 (정상적인 동작)
    if (plates == null || plates.isEmpty) {
      return null;
    }

    // 조건을 만족하는 plate가 있는지 확인
    return plates.firstWhere(
      (plate) => plate.isSelected && plate.whoSelected == userName,
      orElse: () => PlateModel(
        id: '',
        // 빈 값 설정
        plateNumber: '',
        type: '',
        entryTime: DateTime.now(),
        location: '',
        area: '',
        userName: '',
        isSelected: false,
        memoList: [],
      ), // 🔥 PlateModel 기본값 반환
    );
  }

  /// 🔹 특정 번호판을 컬렉션에서 찾기
  PlateModel? _findPlate(String collection, String plateNumber) {
    try {
      return _data[collection]?.firstWhere(
        (plate) => plate.plateNumber == plateNumber,
      );
    } catch (e) {
      debugPrint("🚨 Error in _findPlate: $e");
      return null;
    }
  }

  /// 🔹 선택된 번호판을 삭제
  Future<void> deletePlateFromParkingRequest(String plateNumber, String area) async {
    final documentId = '${plateNumber}_$area';

    try {
      // 🔹 1️⃣ Firestore에서 삭제
      await _repository.deleteDocument('parking_requests', documentId);

      // 🔹 2️⃣ 내부 리스트에서 데이터 삭제
      _data['parking_requests']?.removeWhere((plate) => plate.plateNumber == plateNumber);

      notifyListeners(); // 🔄 UI 갱신
      debugPrint("✅ 번호판 삭제 완료: $plateNumber");
    } catch (e) {
      debugPrint("🚨 번호판 삭제 실패: $e");
    }
  }

  /// 🔹 '입차 완료' 컬렉션에서 번호판 삭제
  Future<void> deletePlateFromParkingCompleted(String plateNumber, String area) async {
    final documentId = '${plateNumber}_$area';

    try {
      // 🔹 1️⃣ Firestore에서 삭제
      await _repository.deleteDocument('parking_completed', documentId);

      // 🔹 2️⃣ 내부 리스트에서 데이터 삭제
      _data['parking_completed']?.removeWhere((plate) => plate.plateNumber == plateNumber);

      notifyListeners(); // 🔄 UI 갱신
      debugPrint("✅ 번호판 삭제 완료 (입차 완료 컬렉션): $plateNumber");
    } catch (e) {
      debugPrint("🚨 번호판 삭제 실패 (입차 완료 컬렉션): $e");
    }
  }

  /// 🔹 특정 plate의 location을 업데이트하는 메서드 (새로 추가)
  void goBackToParkingRequest(String plateNumber, String? newLocation) {
    for (final collection in _data.keys) {
      final plates = _data[collection];
      if (plates != null) {
        final index = plates.indexWhere((plate) => plate.plateNumber == plateNumber);
        if (index != -1) {
          final oldPlate = plates[index];

          // ✅ `newLocation`이 `null`이거나 빈 값이면 "미지정" 설정
          final updatedLocation = (newLocation == null || newLocation.trim().isEmpty) ? "미지정" : newLocation;

          plates.removeAt(index);

          final updatedPlate = PlateModel(
            id: oldPlate.id,
            plateNumber: oldPlate.plateNumber,
            type: oldPlate.type,
            entryTime: oldPlate.entryTime,
            location: updatedLocation,
            // ✅ location 변경 적용
            area: oldPlate.area,
            userName: oldPlate.userName,
            isSelected: oldPlate.isSelected,
            whoSelected: oldPlate.whoSelected,
            adjustmentType: oldPlate.adjustmentType,
            memoList: oldPlate.memoList,
            basicStandard: oldPlate.basicStandard,
            basicAmount: oldPlate.basicAmount,
            addStandard: oldPlate.addStandard,
            addAmount: oldPlate.addAmount,
          );

          plates.insert(index, updatedPlate);

          notifyListeners(); // 🔄 UI 갱신
          return;
        }
      }
    }
  }

  Future<void> deletePlateFromDepartureRequest(String plateNumber, String area) async {
    final documentId = '${plateNumber}_$area';

    try {
      // 🔹 1️⃣ Firestore에서 삭제
      await _repository.deleteDocument('departure_requests', documentId);

      // 🔹 2️⃣ 내부 리스트에서 데이터 삭제
      _data['departure_requests']?.removeWhere((plate) => plate.plateNumber == plateNumber);

      notifyListeners(); // 🔄 UI 갱신
      debugPrint("✅ 번호판 삭제 완료 (입차 완료 컬렉션): $plateNumber");
    } catch (e) {
      debugPrint("🚨 번호판 삭제 실패 (입차 완료 컬렉션): $e");
    }
  }

  /// 🔹 선택된 번호판을 '입차 완료' 상태로 이동
  Future<void> movePlateToCompleted(String plateNumber, String location) async {
    final selectedPlate = _findPlate('parking_requests', plateNumber);
    if (selectedPlate != null) {
      // 새로운 PlateModel 인스턴스 생성
      final updatedPlate = PlateModel(
        id: selectedPlate.id,
        plateNumber: selectedPlate.plateNumber,
        type: '입차 완료',
        // ✅ 상태 변경
        entryTime: selectedPlate.entryTime,
        location: location,
        // ✅ 새로운 위치 적용
        area: selectedPlate.area,
        userName: selectedPlate.userName,
        isSelected: false,
        // ✅ 선택 해제
        whoSelected: null,
        adjustmentType: selectedPlate.adjustmentType,
        memoList: selectedPlate.memoList,
        basicStandard: selectedPlate.basicStandard,
        basicAmount: selectedPlate.basicAmount,
        addStandard: selectedPlate.addStandard,
        addAmount: selectedPlate.addAmount,
      );

      final documentId = '${plateNumber}_${selectedPlate.area}';

      try {
        // 🔹 1️⃣ Firestore에서 `parking_requests` 문서 삭제
        await _repository.deleteDocument('parking_requests', documentId);

        // 🔹 2️⃣ Firestore에 `parking_completed` 문서 추가
        await _repository.addOrUpdateDocument('parking_completed', documentId, {
          'plate_number': updatedPlate.plateNumber,
          'type': updatedPlate.type,
          'entry_time': updatedPlate.entryTime,
          'location': updatedPlate.location,
          'area': updatedPlate.area,
          'user_name': updatedPlate.userName,
          'adjustment_type': updatedPlate.adjustmentType,
          'memo_list': updatedPlate.memoList,
          'isSelected': updatedPlate.isSelected,
          'who_selected': updatedPlate.whoSelected,
          'basic_standard': updatedPlate.basicStandard,
          'basic_amount': updatedPlate.basicAmount,
          'add_standard': updatedPlate.addStandard,
          'add_amount': updatedPlate.addAmount,
        });

        // 🔹 3️⃣ 내부 리스트에서 데이터 이동
        _data['parking_requests']?.removeWhere((plate) => plate.plateNumber == plateNumber);
        _data['parking_completed']?.add(updatedPlate);

        notifyListeners(); // 🔄 UI 갱신
      } catch (e) {
        debugPrint('🚨 Firestore 데이터 이동 실패: $e');
      }
    }
  }

  Future<void> updatePlateStatus({
    required String plateNumber,
    required String area,
    required String fromCollection,
    required String toCollection,
    required String newType,
  }) async {
    await transferData(
      fromCollection: fromCollection,
      toCollection: toCollection,
      plateNumber: plateNumber,
      area: area,
      newType: newType,
    );
  }

// ✅ 기존 중복된 함수들을 제거하고 `updatePlateStatus()`로 통합
  Future<void> setParkingCompleted(String plateNumber, String area) async {
    await updatePlateStatus(
      plateNumber: plateNumber,
      area: area,
      fromCollection: 'parking_requests',
      toCollection: 'parking_completed',
      newType: '입차 완료',
    );
  }

  Future<void> setDepartureRequested(String plateNumber, String area) async {
    await updatePlateStatus(
      plateNumber: plateNumber,
      area: area,
      fromCollection: 'parking_completed',
      // ✅ 기존 컬렉션
      toCollection: 'departure_requests',
      // ✅ 이동할 컬렉션
      newType: '출차 요청',
    );

    // ✅ 상태 변경 후 UI 업데이트
    notifyListeners();
  }

  Future<void> setDepartureCompleted(String plateNumber, String area) async {
    await updatePlateStatus(
      plateNumber: plateNumber,
      area: area,
      fromCollection: 'departure_requests',
      toCollection: 'departure_completed',
      newType: '출차 완료',
    );
  }

  /// 특정 지역에서 사용 가능한 주차 구역 가져오기
  Future<List<String>> getAvailableLocations(String area) async {
    return await _repository.getAvailableLocations(area);
  }

  /// 지역 상태와 동기화
  void syncWithAreaState(String area) {
    notifyListeners();
  }
}
