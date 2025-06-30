import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/snackbar_helper.dart';
import 'input_plate_service.dart';

import '../../states/bill/bill_state.dart';
import '../../states/user/user_state.dart';
import '../../states/area/area_state.dart';

class InputPlateController {
  final TextEditingController controllerFrontDigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController customStatusController = TextEditingController();

  bool showKeypad = true;
  bool isLoading = false;
  bool isLocationSelected = false;
  String dropdownValue = '전국';
  String? selectedBill;
  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;

  bool isThreeDigit = true;

  String? fetchedCustomStatus;

  List<String> statuses = [];
  List<bool> isSelected = [];
  List<String> selectedStatuses = [];

  /// 불러온 상태 (불러오면 InputStatusOnTapSection에 반영)
  List<String> fetchedStatusList = [];

  final List<String> regions = [
    '전국', '강원', '경기', '경남', '경북', '광주', '대구', '대전',
    '부산', '서울', '울산', '인천', '전남', '전북', '제주',
    '충남', '충북', '국기', '대표', '영사', '외교', '임시',
    '준영', '준외', '협정',
  ];

  late TextEditingController activeController;
  final List<XFile> capturedImages = [];

  InputPlateController() {
    activeController = controllerFrontDigit;
    _addInputListeners();
  }

  void _addInputListeners() {
    controllerFrontDigit.addListener(_handleInputChange);
    controllerMidDigit.addListener(_handleInputChange);
    controllerBackDigit.addListener(_handleInputChange);
  }

  void _removeInputListeners() {
    controllerFrontDigit.removeListener(_handleInputChange);
    controllerMidDigit.removeListener(_handleInputChange);
    controllerBackDigit.removeListener(_handleInputChange);
  }

  void _handleInputChange() {
    // 필요 시 입력 변화를 처리
  }

  void setActiveController(TextEditingController controller) {
    activeController = controller;
    showKeypad = true;
  }

  void setFrontDigitMode(bool isThree) {
    isThreeDigit = isThree;
    controllerFrontDigit.clear();
    setActiveController(controllerFrontDigit);
  }

  void clearInput() {
    controllerFrontDigit.clear();
    controllerMidDigit.clear();
    controllerBackDigit.clear();
    activeController = controllerFrontDigit;
    showKeypad = true;
  }

  void clearLocation() {
    locationController.clear();
    isLocationSelected = false;
  }

  void resetForm() {
    clearInput();
    clearLocation();
    capturedImages.clear();
    selectedStatuses.clear();
    selectedBill = null;
    selectedBasicStandard = 0;
    selectedBasicAmount = 0;
    selectedAddStandard = 0;
    selectedAddAmount = 0;
    customStatusController.clear();
    fetchedCustomStatus = null;
    fetchedStatusList = [];
    isSelected = List.generate(statuses.length, (_) => false);
    isThreeDigit = true;
  }

  String buildPlateNumber() {
    return '${controllerFrontDigit.text}-${controllerMidDigit.text}-${controllerBackDigit.text}';
  }

  bool isInputValid() {
    final validFront = isThreeDigit ? controllerFrontDigit.text.length == 3 : controllerFrontDigit.text.length == 2;
    return validFront && controllerMidDigit.text.length == 1 && controllerBackDigit.text.length == 4;
  }

  void toggleStatus(int index) {
    isSelected[index] = !isSelected[index];
    final status = statuses[index];
    if (isSelected[index]) {
      selectedStatuses.add(status);
    } else {
      selectedStatuses.remove(status);
    }
  }

  void dispose() {
    _removeInputListeners();
    controllerFrontDigit.dispose();
    controllerMidDigit.dispose();
    controllerBackDigit.dispose();
    locationController.dispose();
    customStatusController.dispose();
  }

  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final docId = '${plateNumber}_$area';

    try {
      await FirebaseFirestore.instance.collection('plate_status').doc(docId).delete();
      fetchedCustomStatus = null;
      fetchedStatusList = [];
    } catch (e) {
      debugPrint('❌ customStatus 삭제 실패: $e');
      rethrow;
    }
  }

  /// ✅ Firestore에서 statusList와 customStatus 불러오기
  Future<void> fetchStatusAndMemo(String plateNumber, String area) async {
    final docId = '${plateNumber}_$area';
    final docSnapshot = await FirebaseFirestore.instance
        .collection('plate_status')
        .doc(docId)
        .get();

    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      fetchedCustomStatus = data?['customStatus'];

      final List<dynamic>? savedList = data?['statusList'];
      if (savedList != null) {
        fetchedStatusList = savedList.map((e) => e.toString()).toList();
      }
    } else {
      fetchedCustomStatus = null;
      fetchedStatusList = [];
    }
  }

  Future<void> submitPlateEntry(BuildContext context, bool mounted, VoidCallback refreshUI) async {
    final plateNumber = buildPlateNumber();
    final areaState = context.read<AreaState>();
    final area = areaState.currentArea;
    final division = areaState.currentDivision;
    final userName = context.read<UserState>().name;
    final billList = context.read<BillState>().bills;

    if (billList.isNotEmpty && selectedBill == null) {
      showFailedSnackbar(context, '정산 유형을 선택해주세요');
      return;
    }

    isLoading = true;
    refreshUI();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final uploadedUrls = await InputPlateService.uploadCapturedImages(
        capturedImages,
        plateNumber,
        area,
        userName,
        division,
      );

      final wasSuccessful = await InputPlateService.registerPlateEntry(
        context: context,
        plateNumber: plateNumber,
        location: locationController.text,
        isLocationSelected: isLocationSelected,
        imageUrls: uploadedUrls,
        selectedBill: selectedBill,
        selectedStatuses: selectedStatuses,
        basicStandard: selectedBasicStandard,
        basicAmount: selectedBasicAmount,
        addStandard: selectedAddStandard,
        addAmount: selectedAddAmount,
        region: dropdownValue,
        customStatus: customStatusController.text.trim().isNotEmpty
            ? customStatusController.text
            : fetchedCustomStatus ?? '',
      );

      /// ✅ 상태 메모 + 상태 리스트 Firestore에 저장
      await FirebaseFirestore.instance.collection('plate_status').doc('${plateNumber}_$area').set(
        {
          'customStatus': customStatusController.text.trim(),
          'statusList': selectedStatuses,
          'updatedAt': FieldValue.serverTimestamp(),
          'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
          'createdBy': userName,
        },
        SetOptions(merge: true),
      );

      if (mounted) {
        Navigator.of(context).pop();
        if (wasSuccessful) {
          showSuccessSnackbar(context, '차량 정보 등록 완료');
          resetForm();
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showFailedSnackbar(context, '등록 실패: ${e.toString()}');
      }
    } finally {
      isLoading = false;
      if (mounted) refreshUI();
    }
  }
}
