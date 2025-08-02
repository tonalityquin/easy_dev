import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../models/bill_model.dart';
import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

import '../../models/regular_bill_model.dart';
import '../../states/plate/plate_state.dart';
import '../../states/bill/bill_state.dart';
import '../../states/area/area_state.dart';

import '../type_pages/debugs/firestore_logger.dart';
import '../../utils/snackbar_helper.dart';
import 'modify_plate_service.dart';

import '../../repositories/plate/firestore_plate_repository.dart';

// 생략된 import는 동일
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

  final FirestorePlateRepository _plateRepo = FirestorePlateRepository();

  CameraController? cameraController;
  bool isCameraInitialized = false;
  bool _isDisposing = false;

  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;
  String? selectedBill;
  String selectedBillType = '일반'; // ✅ 추가됨
  String dropdownValue = '전국';

  bool isLocationSelected = false;

  String? fetchedCustomStatus;
  List<String> initialSelectedStatuses = [];

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
    } catch (e) {
      debugPrint('❌ 카메라 dispose 중 오류: $e');
    }
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
    selectedBill = plate.billingType;
    selectedBasicStandard = plate.basicStandard ?? 0;
    selectedBasicAmount = plate.basicAmount ?? 0;
    selectedAddStandard = plate.addStandard ?? 0;
    selectedAddAmount = plate.addAmount ?? 0;
    isLocationSelected = locationController.text.isNotEmpty;

    fetchedCustomStatus = plate.customStatus;
    customStatusController.text = plate.customStatus ?? '';
    initialSelectedStatuses = List<String>.from(plate.statusList);
  }

  void onBillTypeChanged(String type) {
    if (type != selectedBillType) {
      debugPrint('❌ 정산 유형 변경은 허용되지 않습니다. 기존: $selectedBillType → 시도: $type');
      return;
    }

    selectedBill = null;
    selectedBasicAmount = 0;
    selectedBasicStandard = 0;
    selectedAddAmount = 0;
    selectedAddStandard = 0;
  }

  void applyBillDefaults(String? billName) {
    if (billName == null) return;

    final billState = context.read<BillState>();
    final List<dynamic> allBills = [...billState.generalBills, ...billState.regularBills];

    final selected = allBills.firstWhere(
      (bill) => (bill is BillModel || bill is RegularBillModel) && bill.countType == billName,
      orElse: () => null,
    );

    if (selected == null) return;

    selectedBill = selected.countType;

    if (selected is BillModel) {
      selectedBillType = '일반'; // ✅ 추가
      selectedBasicAmount = selected.basicAmount ?? 0;
      selectedBasicStandard = selected.basicStandard ?? 0;
      selectedAddAmount = selected.addAmount ?? 0;
      selectedAddStandard = selected.addStandard ?? 0;
    } else if (selected is RegularBillModel) {
      selectedBillType = '정기'; // ✅ 추가
      selectedBasicAmount = selected.regularAmount;
      selectedBasicStandard = selected.regularDurationHours;
      selectedAddAmount = 0;
      selectedAddStandard = 0;
    }
  }

  Future<void> updateCustomStatusToFirestore() async {
    final plateNumber = plate.plateNumber;
    final area = context.read<AreaState>().currentArea;

    try {
      await _plateRepo.setPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: customStatusController.text.trim(),
        statusList: initialSelectedStatuses,
        createdBy: 'devAdmin020',
      );
      debugPrint('✅ Firestore 문서 업데이트 완료: $plateNumber-$area');
    } catch (e) {
      debugPrint('❌ Firestore 문서 업데이트 실패: $e');
    }
  }

  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = plate.plateNumber.replaceAll('-', '');
    final area = context.read<AreaState>().currentArea;

    try {
      await _plateRepo.deletePlateStatus(plateNumber, area);
      fetchedCustomStatus = null;
    } catch (e) {
      debugPrint('❌ customStatus 삭제 실패: $e');
      rethrow;
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

  Future<void> handleAction(VoidCallback onSuccess, List<String> selectedStatuses) async {
    final billState = context.read<BillState>();
    final allBills = [...billState.generalBills, ...billState.regularBills];

    if (allBills.isNotEmpty && (selectedBill == null || selectedBill!.isEmpty)) {
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
      selectedBill: selectedBill,
      dropdownValue: dropdownValue,
    );

    final plateNumber = service.composePlateNumber();
    final newLocation = locationController.text;
    final newBillingType = selectedBill;
    final updatedCustomStatus = customStatusController.text.trim();

    await FirestoreLogger().log('🛠️ Modify 시작: $plateNumber', level: 'called');

    final mergedImageUrls = await service.uploadAndMergeImages(plateNumber);
    await FirestoreLogger().log('✅ 이미지 병합 완료 (${mergedImageUrls.length})', level: 'success');

    final success = await service.updatePlateInfo(
      plateNumber: plateNumber,
      imageUrls: mergedImageUrls,
      newLocation: newLocation,
      newBillingType: newBillingType,
    );

    if (success) {
      final area = context.read<AreaState>().currentArea;

      await FirestoreLogger().log('📤 상태 정보 Firestore 업데이트 시도 ($plateNumber-$area)', level: 'called');

      await _plateRepo.setPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: updatedCustomStatus,
        statusList: selectedStatuses,
        createdBy: 'devAdmin020',
      );

      await FirestoreLogger().log('✅ 상태 정보 업데이트 완료', level: 'success');

      await FirebaseFirestore.instance.collection('plates').doc(plate.id).update({
        'customStatus': updatedCustomStatus,
        'statusList': selectedStatuses,
      });

      await FirestoreLogger().log('✅ plates 문서 업데이트 완료', level: 'success');

      final updatedPlate = plate.copyWith(
        billingType: newBillingType,
        basicStandard: selectedBasicStandard,
        basicAmount: selectedBasicAmount,
        addStandard: selectedAddStandard,
        addAmount: selectedAddAmount,
        location: newLocation,
        statusList: selectedStatuses,
        region: dropdownValue,
        imageUrls: mergedImageUrls,
        customStatus: updatedCustomStatus,
        isSelected: false,
        selectedBy: null,
      );

      final plateState = context.read<PlateState>();
      await plateState.togglePlateIsSelected(
        collection: collectionKey,
        plateNumber: plateNumber,
        userName: plate.userName,
        onError: (error) async {
          await FirestoreLogger().log('⚠️ togglePlateIsSelected 에러: $error', level: 'error');
        },
      );

      await plateState.updatePlateLocally(collectionKey, updatedPlate);

      await FirestoreLogger().log('🎉 Plate 수정 완료', level: 'success');

      onSuccess();
    } else {
      await FirestoreLogger().log('❌ Plate 수정 실패', level: 'error');
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
