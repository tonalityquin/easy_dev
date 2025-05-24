import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/snackbar_helper.dart';

import 'input_plate_service.dart';

import '../../states/adjustment/adjustment_state.dart';
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
  String? selectedAdjustment;
  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;

  bool isThreeDigit = true;

  String? fetchedCustomStatus;

  List<String> statuses = [];
  List<bool> isSelected = [];
  List<String> selectedStatuses = [];

  final List<String> regions = [
    '전국',
    '강원',
    '경기',
    '경남',
    '경북',
    '광주',
    '대구',
    '대전',
    '부산',
    '서울',
    '울산',
    '인천',
    '전남',
    '전북',
    '제주',
    '충남',
    '충북',
    '국기',
    '대표',
    '영사',
    '외교',
    '임시',
    '준영',
    '준외',
    '협정',
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
    // 입력 변화 감지 로직 필요 시 추가
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
    selectedAdjustment = null;
    selectedBasicStandard = 0;
    selectedBasicAmount = 0;
    selectedAddStandard = 0;
    selectedAddAmount = 0;
    customStatusController.clear();
    fetchedCustomStatus = null;
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
      final docRef = FirebaseFirestore.instance.collection('plate_status').doc(docId);
      await docRef.delete();
      fetchedCustomStatus = null;
    } catch (e) {
      debugPrint('❌ customStatus 삭제 실패: $e');
      rethrow;
    }
  }

  Future<void> handleAction(BuildContext context, bool mounted, VoidCallback refreshUI) async {
    final plateNumber = buildPlateNumber();
    final areaState = context.read<AreaState>();
    final area = areaState.currentArea;
    final division = areaState.currentDivision; // ✅ 지역 기반 division 사용
    final userName = context.read<UserState>().name;
    final adjustmentList = context.read<AdjustmentState>().adjustments;

    if (adjustmentList.isNotEmpty && selectedAdjustment == null) {
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
      final uploaded = await InputPlateService.uploadCapturedImages(
        capturedImages,
        plateNumber,
        area,
        userName,
        division,
      );

      final wasSuccessful = await InputPlateService.saveInputPlateEntry(
        context: context,
        plateNumber: plateNumber,
        location: locationController.text,
        isLocationSelected: isLocationSelected,
        imageUrls: uploaded,
        selectedAdjustment: selectedAdjustment,
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
