import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_helper.dart';
import 'input_plate_service.dart';
import '../../states/adjustment/adjustment_state.dart';
import '../../states/user/user_state.dart';
import '../../states/area/area_state.dart';

class InputPlateController {
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

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
    '협정'
  ];

  late TextEditingController activeController;

  final List<XFile> capturedImages = [];

  InputPlateController() {
    activeController = controller3digit;
    _addInputListeners();
  }

  void _addInputListeners() {
    controller3digit.addListener(_handleInputChange);
    controller1digit.addListener(_handleInputChange);
    controller4digit.addListener(_handleInputChange);
  }

  void _removeInputListeners() {
    controller3digit.removeListener(_handleInputChange);
    controller1digit.removeListener(_handleInputChange);
    controller4digit.removeListener(_handleInputChange);
  }

  void _handleInputChange() {
    // 추후 입력 검증, 포맷 변경에 활용 가능
  }

  void setActiveController(TextEditingController controller) {
    activeController = controller;
    showKeypad = true;
  }

  void setDigitMode(bool isThree) {
    isThreeDigit = isThree;
    controller3digit.clear();
    setActiveController(controller3digit);
  }

  void clearInput() {
    controller3digit.clear();
    controller1digit.clear();
    controller4digit.clear();
    activeController = controller3digit;
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
    isSelected = List.generate(statuses.length, (_) => false);
    isThreeDigit = true;
  }

  String buildPlateNumber() {
    return '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}';
  }

  bool isInputValid() {
    final validFront = isThreeDigit ? controller3digit.text.length == 3 : controller3digit.text.length == 2;

    return validFront && controller1digit.text.length == 1 && controller4digit.text.length == 4;
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
    controller3digit.dispose();
    controller1digit.dispose();
    controller4digit.dispose();
    locationController.dispose();
  }

  Future<void> handleAction(BuildContext context, bool mounted, VoidCallback refreshUI) async {
    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
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
