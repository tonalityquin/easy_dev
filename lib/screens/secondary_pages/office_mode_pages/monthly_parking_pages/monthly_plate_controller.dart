import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../../type_pages/debugs/firestore_logger.dart';
import '../../../../utils/snackbar_helper.dart';
import 'monthly_plate_service.dart';

import '../../../../states/bill/bill_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../states/area/area_state.dart';
import '../../../../repositories/plate/firestore_plate_repository.dart';

class MonthlyPlateController {
  final TextEditingController controllerFrontDigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController customStatusController = TextEditingController();
  final TextEditingController? nameController;
  final TextEditingController? amountController;
  final TextEditingController? durationController;
  final TextEditingController? startDateController;
  final TextEditingController? endDateController;

  final FirestorePlateRepository _plateRepo = FirestorePlateRepository();

  bool showKeypad = true;
  bool isLoading = false;
  bool isLocationSelected = false;
  String dropdownValue = '전국';

  String selectedBillType = '일반';
  String? _selectedBill;

  String? get selectedBill => _selectedBill;

  set selectedBill(String? value) => _selectedBill = value;

  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;

  bool isThreeDigit = true;

  String? fetchedCustomStatus;

  List<String> statuses = [];
  List<bool> isSelected = [];
  List<String> selectedStatuses = [];
  List<String> fetchedStatusList = [];

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

  /// ✅ 정기주차 관련 입력 필드 (외부에서 주입됨)
  TextEditingController? regularAmountController;
  TextEditingController? regularDurationController;
  String? selectedRegularType;

  MonthlyPlateController({
    this.regularAmountController,
    this.regularDurationController,
    this.selectedRegularType,
    this.nameController,
    this.amountController,
    this.durationController,
    this.startDateController,
    this.endDateController,
  }) {
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

  void _handleInputChange() {}

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
    _selectedBill = null;
    selectedBasicStandard = 0;
    selectedBasicAmount = 0;
    selectedAddStandard = 0;
    selectedAddAmount = 0;
    customStatusController.clear();
    fetchedCustomStatus = null;
    fetchedStatusList = [];
    isSelected = List.generate(statuses.length, (_) => false);
    isThreeDigit = true;
    selectedBillType = '일반';

    regularAmountController?.clear();
    regularDurationController?.clear();
    selectedRegularType = null;
  }

  String buildPlateNumber() {
    return '${controllerFrontDigit.text}-${controllerMidDigit.text}-${controllerBackDigit.text}';
  }

  bool isInputValid() {
    final validFront = isThreeDigit ? controllerFrontDigit.text.length == 3 : controllerFrontDigit.text.length == 2;
    return validFront && controllerMidDigit.text.length == 1 && controllerBackDigit.text.length == 4;
  }

  void dispose() {
    _removeInputListeners();
    controllerFrontDigit.dispose();
    controllerMidDigit.dispose();
    controllerBackDigit.dispose();
    locationController.dispose();
    customStatusController.dispose();
  }

  void setSelectedBill(String? billId, BuildContext context) {
    _selectedBill = billId;

    if (billId == null) {
      selectedBasicStandard = 0;
      selectedBasicAmount = 0;
      selectedAddStandard = 0;
      selectedAddAmount = 0;
      return;
    }

    final billState = context.read<BillState>();

    if (selectedBillType == '일반') {
      final matched = billState.generalBills.firstWhere(
        (b) => b.countType == billId,
        orElse: () => billState.emptyModel,
      );

      selectedBasicStandard = matched.basicStandard ?? 0;
      selectedBasicAmount = matched.basicAmount ?? 0;
      selectedAddStandard = matched.addStandard ?? 0;
      selectedAddAmount = matched.addAmount ?? 0;
    } else {
      selectedBasicStandard = 0;
      selectedBasicAmount = 0;
      selectedAddStandard = 0;
      selectedAddAmount = 0;
    }
  }

  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;

    try {
      await FirestoreLogger().log('🗑️ 상태 메모 삭제 시도: $plateNumber-$area', level: 'called');
      await _plateRepo.deletePlateStatus(plateNumber, area);
      fetchedCustomStatus = null;
      fetchedStatusList = [];
      await FirestoreLogger().log('✅ 상태 메모 삭제 성공: $plateNumber-$area', level: 'success');
    } catch (e) {
      await FirestoreLogger().log('❌ 상태 메모 삭제 실패: $e', level: 'error');
      rethrow;
    }
  }

  Future<void> fetchStatusAndMemo(String plateNumber, String area) async {
    await FirestoreLogger().log('🔍 상태/메모 조회 시도: $plateNumber-$area', level: 'called');
    final data = await _plateRepo.getPlateStatus(plateNumber, area);

    if (data != null) {
      await FirestoreLogger().log('✅ 상태/메모 조회 성공: $plateNumber-$area', level: 'success');
      fetchedCustomStatus = data['customStatus'];
      final List<dynamic>? savedList = data['statusList'];
      if (savedList != null) {
        fetchedStatusList = savedList.map((e) => e.toString()).toList();
      }
    } else {
      await FirestoreLogger().log('📭 상태/메모 없음: $plateNumber-$area', level: 'info');
      fetchedCustomStatus = null;
      fetchedStatusList = [];
    }
  }

  Future<void> submitPlateEntry(
    BuildContext context,
    bool mounted,
    VoidCallback refreshUI,
  ) async {
    final plateNumber = buildPlateNumber();
    final areaState = context.read<AreaState>();
    final area = areaState.currentArea;
    final division = areaState.currentDivision;
    final userName = context.read<UserState>().name;

    // ✅ 항상 정기 주차로 처리
    selectedBillType = '정기';

    isLoading = true;
    refreshUI();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await FirestoreLogger().log('🚀 plate 등록 시작: $plateNumber', level: 'called');

      final uploadedUrls = await MonthlyPlateService.uploadCapturedImages(
        capturedImages,
        plateNumber,
        area,
        userName,
        division,
      );

      await FirestoreLogger().log('✅ 이미지 업로드 완료: ${uploadedUrls.length}', level: 'success');

      final wasSuccessful = await MonthlyPlateService.registerPlateEntry(
        context: context,
        plateNumber: plateNumber,
        location: locationController.text,
        isLocationSelected: isLocationSelected,
        imageUrls: uploadedUrls,
        selectedBill: _selectedBill,
        selectedStatuses: selectedStatuses,
        basicStandard: selectedBasicStandard,
        basicAmount: selectedBasicAmount,
        addStandard: selectedAddStandard,
        addAmount: selectedAddAmount,
        region: dropdownValue,
        customStatus:
            customStatusController.text.trim().isNotEmpty ? customStatusController.text : fetchedCustomStatus ?? '',
      );

      await _plateRepo.setPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: customStatusController.text.trim(),
        statusList: selectedStatuses,
        createdBy: userName,
      );

      // ✅ 무조건 정기 정산으로 저장
      await _plateRepo.setMonthlyPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: customStatusController.text.trim(),
        statusList: selectedStatuses,
        createdBy: userName,
        countType: nameController?.text.trim() ?? '',
        regularAmount: int.tryParse(amountController?.text.trim() ?? '') ?? 0,
        regularDurationHours: int.tryParse(durationController?.text.trim() ?? '') ?? 0,
        regularType: selectedRegularType ?? '정기 주차',
        startDate: startDateController?.text.trim() ?? '',
        endDate: endDateController?.text.trim() ?? '',
      );

      if (mounted) {
        Navigator.of(context).pop();
        if (wasSuccessful) {
          showSuccessSnackbar(context, '차량 정보 등록 완료');
          resetForm();
        }
      }

      await FirestoreLogger().log('🎉 plate 등록 완료: $plateNumber', level: 'success');
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showFailedSnackbar(context, '등록 실패: ${e.toString()}');
      }
      await FirestoreLogger().log('❌ plate 등록 실패: $e', level: 'error');
    } finally {
      isLoading = false;
      if (mounted) refreshUI();
    }
  }
}
