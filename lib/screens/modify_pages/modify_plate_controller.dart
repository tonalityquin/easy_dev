import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

import '../../states/plate/plate_state.dart';
import '../../states/adjustment/adjustment_state.dart';
import '../../states/status/status_state.dart';
import '../../states/area/area_state.dart';

import '../../utils/snackbar_helper.dart';
import 'modify_plate_service.dart';

class ModifyPlateController {
  final BuildContext context;
  final PlateModel plate;
  final PlateType collectionKey;

  final TextEditingController controllerFrontdigit;
  final TextEditingController controllerMidDigit;
  final TextEditingController controllerBackDigit;
  final TextEditingController locationController;
  final TextEditingController customStatusController = TextEditingController();

  final List<XFile> capturedImages;
  final List<String> existingImageUrls;

  CameraController? cameraController;
  bool isCameraInitialized = false;
  bool _isDisposing = false;

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

  String? fetchedCustomStatus;

  final List<String> _regions = [
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

  List<String> get regions => _regions;

  ModifyPlateController({
    required this.context,
    required this.plate,
    required this.collectionKey,
    required this.controllerFrontdigit,
    required this.controllerMidDigit,
    required this.controllerBackDigit,
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
    final cameras = await availableCameras();
    final backCamera = cameras.first;
    cameraController = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await cameraController!.initialize();
    isCameraInitialized = true;
  }

  Future<XFile?> captureImage() async {
    if (cameraController == null || !cameraController!.value.isInitialized) return null;
    if (cameraController!.value.isTakingPicture) return null;

    try {
      final image = await cameraController!.takePicture();
      capturedImages.add(image);
      return image;
    } catch (e) {
      return null;
    }
  }

  Future<void> disposeCamera() async {
    if (_isDisposing) return;
    _isDisposing = true;

    try {
      if (cameraController?.value.isInitialized ?? false) {
        await cameraController?.dispose();
      }
      cameraController = null;
      isCameraInitialized = false;
    } catch (_) {}
    _isDisposing = false;
  }

  void initializeFieldValues() {
    final plateNum = plate.plateNumber.replaceAll('-', '');
    final regExp = RegExp(r'^(\d{2,3})([가-힣]?)(\d{4})$');
    final match = regExp.firstMatch(plateNum);

    if (match != null) {
      controllerFrontdigit.text = match.group(1) ?? '';
      controllerMidDigit.text = match.group(2) ?? '';
      controllerBackDigit.text = match.group(3) ?? '';
    } else {
      controllerFrontdigit.text = plateNum.length >= 7 ? plateNum.substring(0, 3) : '';
      controllerMidDigit.text = '-';
      controllerBackDigit.text = plateNum.length >= 7 ? plateNum.substring(3) : '';
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

    fetchedCustomStatus = plate.customStatus;
    customStatusController.text = plate.customStatus ?? '';
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

  /// 🔁 Firestore adjustment 컬렉션에서 기본값을 가져와 필드 업데이트
  void applyAdjustmentDefaults(String? adjustmentName) {
    if (adjustmentName == null) return;

    final adjustmentState = context.read<AdjustmentState>();
    final selected = adjustmentState.adjustments.firstWhere(
          (a) => a.countType == adjustmentName,
      orElse: () => adjustmentState.emptyModel,
    );

    selectedAdjustment = selected.countType;
    selectedBasicAmount = selected.basicAmount;
    selectedBasicStandard = selected.basicStandard;
    selectedAddAmount = selected.addAmount;
    selectedAddStandard = selected.addStandard;
  }


  Future<void> updateCustomStatusToFirestore() async {
    final plateNumber = plate.plateNumber;
    final area = context.read<AreaState>().currentArea;
    final docId = '${plateNumber}_$area';

    try {
      final docRef = FirebaseFirestore.instance.collection('plate_status').doc(docId);

      await docRef.set({
        'customStatus': customStatusController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
        'createdBy': 'devAdmin020',
      }, SetOptions(merge: true));

      debugPrint('✅ Firestore 문서 업데이트 완료: $docId');
    } catch (e) {
      debugPrint('❌ Firestore 문서 업데이트 실패: $e');
    }
  }

  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = plate.plateNumber.replaceAll('-', '');
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

  void toggleStatus(int index) {
    isSelected[index] = !isSelected[index];
    final status = statuses[index];
    if (isSelected[index]) {
      selectedStatuses.add(status);
    } else {
      selectedStatuses.remove(status);
    }
  }

  void clearInputs() {
    controllerFrontdigit.clear();
    controllerMidDigit.clear();
    controllerBackDigit.clear();
  }

  void clearLocation() {
    locationController.clear();
    isLocationSelected = false;
  }

  String buildPlateNumber() {
    return '${controllerFrontdigit.text}${controllerMidDigit.text}${controllerBackDigit.text}';
  }

  Future<void> handleAction(VoidCallback onSuccess) async {
    final adjustmentList = context.read<AdjustmentState>().adjustments;

    if (adjustmentList.isNotEmpty && (selectedAdjustment == null || selectedAdjustment!.isEmpty)) {
      showFailedSnackbar(context, '정산 유형을 선택해주세요');
      return;
    }

    final service = ModifyPlateService(
      context: context,
      capturedImages: capturedImages,
      existingImageUrls: existingImageUrls,
      collectionKey: collectionKey,
      originalPlate: plate,
      controllerFrontdigit: controllerFrontdigit,
      controllerMidDigit: controllerMidDigit,
      controllerBackDigit: controllerBackDigit,
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
    final updatedCustomStatus = customStatusController.text.trim();

    final mergedImageUrls = await service.uploadAndMergeImages(plateNumber);

    final success = await service.updatePlateInfo(
      plateNumber: plateNumber,
      imageUrls: mergedImageUrls,
      newLocation: newLocation,
      newAdjustmentType: newAdjustmentType,
    );

    if (success) {
      final area = context.read<AreaState>().currentArea;
      final statusDocId = '${plateNumber}_$area';
      await FirebaseFirestore.instance.collection('plate_status').doc(statusDocId).set({
        'customStatus': updatedCustomStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(DateTime.now().add(Duration(days: 1))),
        'createdBy': 'devAdmin020',
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('plates').doc(plate.id).update({'customStatus': updatedCustomStatus});

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
        customStatus: updatedCustomStatus,
      );

      final plateState = context.read<PlateState>();
      await plateState.updatePlateLocally(collectionKey, updatedPlate);

      onSuccess();
    }
  }

  void dispose() {
    controllerFrontdigit.dispose();
    controllerMidDigit.dispose();
    controllerBackDigit.dispose();
    locationController.dispose();
    customStatusController.dispose();
    disposeCamera();
  }
}
