import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

import '../../states/plate/plate_state.dart';
import '../../states/adjustment/adjustment_state.dart';
import '../../states/status/status_state.dart';
import '../../states/area/area_state.dart';

import 'modify_plate_service.dart';
import 'utils/modify_camera_helper.dart';
import '../../utils/snackbar_helper.dart';

class ModifyPlateController {
  final BuildContext context;
  final PlateModel plate;
  final PlateType collectionKey;

  final TextEditingController controller3digit;
  final TextEditingController controller1digit;
  final TextEditingController controller4digit;
  final TextEditingController locationController;

  final List<XFile> capturedImages;
  final List<String> existingImageUrls;

  List<String> statuses = [];
  List<String> selectedStatuses = [];
  List<bool> isSelected = [];

  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;
  String? selectedAdjustment;
  String dropdownValue = '전국';

  bool isLocationSelected = false;

  late ModifyCameraHelper cameraHelper;

  final List<String> _regions = [
    '전국', '강원', '경기', '경남', '경북', '광주', '대구', '대전', '부산',
    '서울', '울산', '인천', '전남', '전북', '제주', '충남', '충북',
    '국기', '대표', '영사', '외교', '임시', '준영', '준외', '협정'
  ];

  List<String> get regions => _regions;

  ModifyPlateController({
    required this.context,
    required this.plate,
    required this.collectionKey,
    required this.controller3digit,
    required this.controller1digit,
    required this.controller4digit,
    required this.locationController,
    required this.capturedImages,
    required this.existingImageUrls,
  });

  void initializePlate() {
    if (plate.imageUrls != null) {
      existingImageUrls.addAll(plate.imageUrls!);
    }
  }

  Future<void> initializeCamera() async {
    cameraHelper = ModifyCameraHelper();
    await cameraHelper.initializeInputCamera();
  }

  void initializeFieldValues() {
    final plateNum = plate.plateNumber.replaceAll('-', '');
    final regExp = RegExp(r'^(\\d{2,3})([가-힣]?)(\\d{4})$');
    final match = regExp.firstMatch(plateNum);

    if (match != null) {
      controller3digit.text = match.group(1) ?? '';
      controller1digit.text = match.group(2) ?? '';
      controller4digit.text = match.group(3) ?? '';
    } else {
      debugPrint('번호판 형식을 파싱하지 못했습니다: $plateNum');
    }

    dropdownValue = plate.region ?? '전국';
    locationController.text = plate.location;
    selectedAdjustment = plate.adjustmentType;
    selectedBasicStandard = plate.basicStandard ?? 0;
    selectedBasicAmount = plate.basicAmount ?? 0;
    selectedAddStandard = plate.addStandard ?? 0;
    selectedAddAmount = plate.addAmount ?? 0;
    selectedStatuses = List<String>.from(plate.statusList);
    isLocationSelected = locationController.text.isNotEmpty;
  }

  Future<void> initializeStatuses() async {
    final statusState = context.read<StatusState>();
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;

    int retry = 0;
    while (statusState.statuses.isEmpty && retry < 5) {
      await Future.delayed(const Duration(milliseconds: 500));
      retry++;
    }

    statuses = statusState.statuses
        .where((status) => status.area == currentArea && status.isActive)
        .map((status) => status.name)
        .toList();

    isSelected = statuses.map((s) => selectedStatuses.contains(s)).toList();
  }

  Future<bool> refreshAdjustments() async {
    final adjustmentState = context.read<AdjustmentState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      adjustmentState.syncWithAreaAdjustmentState();
    });
    await Future.delayed(const Duration(milliseconds: 500));
    return adjustmentState.adjustments.isNotEmpty;
  }

  void clearInputs() {
    controller3digit.clear();
    controller1digit.clear();
    controller4digit.clear();
  }

  void clearLocation() {
    locationController.clear();
    isLocationSelected = false;
  }

  Future<void> handleAction(VoidCallback onSuccess) async {
    final adjustmentList = context.read<AdjustmentState>().adjustments;

    if (adjustmentList.isNotEmpty &&
        (selectedAdjustment == null || selectedAdjustment!.isEmpty)) {
      showFailedSnackbar(context, '정산 유형을 선택해주세요');
      return;
    }

    final service = ModifyPlateService(
      context: context,
      capturedImages: capturedImages,
      existingImageUrls: existingImageUrls,
      collectionKey: collectionKey,
      originalPlate: plate,
      controller3digit: controller3digit,
      controller1digit: controller1digit,
      controller4digit: controller4digit,
      locationController: locationController,
      selectedStatuses: selectedStatuses,
      selectedBasicStandard: selectedBasicStandard,
      selectedBasicAmount: selectedBasicAmount,
      selectedAddStandard: selectedAddStandard,
      selectedAddAmount: selectedAddAmount,
      selectedAdjustment: selectedAdjustment,
      dropdownValue: dropdownValue,
    );

    final plateNumber = service.composePlateNumber();
    final newLocation = locationController.text;
    final newAdjustmentType = selectedAdjustment;

    final mergedImageUrls = await service.uploadAndMergeImages(plateNumber);

    final success = await service.updatePlateInfo(
      plateNumber: plateNumber,
      imageUrls: mergedImageUrls,
      newLocation: newLocation,
      newAdjustmentType: newAdjustmentType,
    );

    if (success) {
      final updatedPlate = plate.copyWith(
        adjustmentType: newAdjustmentType,
        basicStandard: selectedBasicStandard,
        basicAmount: selectedBasicAmount,
        addStandard: selectedAddStandard,
        addAmount: selectedAddAmount,
        location: newLocation,
        statusList: selectedStatuses,
        region: dropdownValue,
        imageUrls: mergedImageUrls,
      );

      final plateState = context.read<PlateState>();
      await plateState.updatePlateLocally(collectionKey, updatedPlate);

      onSuccess();
    }
  }

  void dispose() {
    controller3digit.dispose();
    controller1digit.dispose();
    controller4digit.dispose();
    locationController.dispose();
    cameraHelper.dispose();
  }
}
