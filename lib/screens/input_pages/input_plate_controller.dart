import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class InputPlateController {
  // 입력 필드 컨트롤러
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  // 상태 값
  bool showKeypad = true;
  bool isLoading = false;
  bool isLocationSelected = false;
  String dropdownValue = '전국';
  String? selectedAdjustment;
  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;

  // 상태 선택
  List<String> statuses = [];
  List<bool> isSelected = [];
  List<String> selectedStatuses = [];

  // 지역 선택
  final List<String> regions = [
    '전국', '강원', '경기', '경남', '경북', '광주', '대구',
    '대전', '부산', '서울', '울산', '인천', '전남',
    '전북', '제주', '충남', '충북'
  ];

  // 입력 포커스 관리
  late TextEditingController activeController;

  // 이미지
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
    // 이 함수는 외부에서 필요 시 override하거나 콜백 처리
  }

  void setActiveController(TextEditingController controller) {
    activeController = controller;
    showKeypad = true;
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
  }

  String buildPlateNumber() {
    return '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}';
  }

  bool isInputValid() {
    return controller3digit.text.length == 3 &&
        controller1digit.text.length == 1 &&
        controller4digit.text.length == 4;
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
}
