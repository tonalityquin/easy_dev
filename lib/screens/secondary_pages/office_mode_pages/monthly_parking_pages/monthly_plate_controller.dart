import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../../type_pages/debugs/firestore_logger.dart';
import '../../../../utils/snackbar_helper.dart';

import '../../../../repositories/plate/firestore_plate_repository.dart';
import '../../../../states/user/user_state.dart';
import '../../../../states/area/area_state.dart';

class MonthlyPlateController {
  // ✅ 차량 번호 입력 필드
  final TextEditingController controllerFrontDigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();

  // ✅ 위치, 상태 메모
  final TextEditingController locationController = TextEditingController();
  final TextEditingController customStatusController = TextEditingController();

  // ✅ 요금/기간 관련 컨트롤러
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
  String selectedBillType = '변동';

  // ✅ 결제 관련 필드
  String specialNote = '';
  bool isExtended = false;

  // 기타 상태 필드
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

  TextEditingController? regularAmountController;
  TextEditingController? regularDurationController;
  String? selectedRegularType;
  String selectedPeriodUnit = '월';

  // 수정 관련
  bool isEditMode = false;
  String? docIdToEdit;

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

  // ---------------------------
  // ✅ UI 강제용: 메모/상태 유효성 헬퍼
  // ---------------------------
  bool get hasStatusOrMemo =>
      customStatusController.text.trim().isNotEmpty || selectedStatuses.isNotEmpty;

  bool _validateBeforeWrite(BuildContext context) {
    // 번호판 유효성
    if (!isInputValid()) {
      showFailedSnackbar(context, '번호판을 올바르게 입력해주세요.');
      return false;
    }
    // 기간 필수
    if ((startDateController?.text.trim().isEmpty ?? true) ||
        (durationController?.text.trim().isEmpty ?? true)) {
      showFailedSnackbar(context, '기간 정보를 입력해주세요.');
      return false;
    }
    // 메모 or 상태 필수
    if (!hasStatusOrMemo) {
      showFailedSnackbar(context, '상태를 선택하거나 메모를 입력해주세요.');
      return false;
    }
    return true;
  }

  void _addInputListeners() {
    controllerFrontDigit.addListener(_handleInputChange);
    controllerMidDigit.addListener(_handleInputChange);
    controllerBackDigit.addListener(_handleInputChange);
    durationController?.addListener(updateEndDateFromDuration);
  }

  void _removeInputListeners() {
    controllerFrontDigit.removeListener(_handleInputChange);
    controllerMidDigit.removeListener(_handleInputChange);
    controllerBackDigit.removeListener(_handleInputChange);
    durationController?.removeListener(updateEndDateFromDuration);
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
    selectedBasicStandard = 0;
    selectedBasicAmount = 0;
    selectedAddStandard = 0;
    selectedAddAmount = 0;
    customStatusController.clear();
    fetchedCustomStatus = null;
    fetchedStatusList = [];
    isSelected = List.generate(statuses.length, (_) => false);
    isThreeDigit = true;
    selectedBillType = '변동';
    regularAmountController?.clear();
    regularDurationController?.clear();
    selectedRegularType = null;
    selectedPeriodUnit = '월';
    specialNote = '';
    isExtended = false;
    isEditMode = false;
    docIdToEdit = null;
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

  void updateEndDateFromDuration() {
    final startText = startDateController?.text.trim();
    final durationText = durationController?.text.trim();
    if (startText == null || durationText == null) return;

    final start = DateTime.tryParse(startText);
    final duration = int.tryParse(durationText);
    if (start == null || duration == null) return;

    Duration offset;
    switch (selectedPeriodUnit) {
      case '일':
        offset = Duration(days: duration);
        break;
      case '주':
        offset = Duration(days: duration * 7);
        break;
      case '월':
      default:
        offset = Duration(days: duration * 30);
        break;
    }

    final end = start.add(offset);
    endDateController?.text = formatDate(end);
  }

  String formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> extendDatesIfNeeded() async {
    if (!isExtended) return;

    final currentEnd = DateTime.tryParse(endDateController?.text ?? '');
    if (currentEnd == null) return;

    final addedDuration = int.tryParse(durationController?.text.trim() ?? '');
    if (addedDuration == null) return;

    Duration offset;
    switch (selectedPeriodUnit) {
      case '일':
        offset = Duration(days: addedDuration);
        break;
      case '주':
        offset = Duration(days: addedDuration * 7);
        break;
      case '월':
      default:
        offset = Duration(days: addedDuration * 30);
        break;
    }

    final newStart = currentEnd;
    final newEnd = currentEnd.add(offset);

    startDateController?.text = formatDate(newStart);
    endDateController?.text = formatDate(newEnd);
  }

  Future<void> recordPaymentHistory(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final userName = context.read<UserState>().name;

    final now = DateTime.now();

    final historyEntry = {
      'paidAt': now.toIso8601String(),
      'paidBy': userName,
      'amount': int.tryParse(amountController?.text.trim() ?? '') ?? 0,
      'note': specialNote,
      'extended': isExtended,
    };

    try {
      final docId = '${plateNumber}_$area';

      await FirebaseFirestore.instance.collection('plate_status').doc(docId).set({
        'payment_history': FieldValue.arrayUnion([historyEntry])
      }, SetOptions(merge: true));

      await FirestoreLogger().log('✅ 결제 로그 저장 완료: $docId');
    } catch (e) {
      await FirestoreLogger().log('❌ 결제 로그 저장 실패: $e');
      rethrow;
    }
  }

  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;

    try {
      await FirestoreLogger().log('🗑️ 상태 메모 삭제 시도: $plateNumber-$area');
      await _plateRepo.deletePlateStatus(plateNumber, area);
      fetchedCustomStatus = null;
      fetchedStatusList = [];
      await FirestoreLogger().log('✅ 상태 메모 삭제 성공: $plateNumber-$area');
    } catch (e) {
      await FirestoreLogger().log('❌ 상태 메모 삭제 실패: $e');
      rethrow;
    }
  }

  // 기존 문서 데이터를 로딩
  Future<void> loadExistingData(Map<String, dynamic> data, {required String docId}) async {
    isEditMode = true;
    docIdToEdit = docId;

    final parts = docId.split('-');
    if (parts.length == 3) {
      controllerFrontDigit.text = parts[0];
      controllerMidDigit.text = parts[1];
      controllerBackDigit.text = parts[2];
    }

    dropdownValue = data['region'] ?? '전국';
    nameController?.text = data['countType'] ?? '';
    amountController?.text = (data['regularAmount'] ?? 0).toString();
    durationController?.text = (data['regularDurationHours'] ?? 0).toString();
    selectedRegularType = data['regularType'] ?? '';
    selectedPeriodUnit = data['periodUnit'] ?? '월';
    startDateController?.text = data['startDate'] ?? '';
    endDateController?.text = data['endDate'] ?? '';
    customStatusController.text = data['customStatus'] ?? '';
    specialNote = data['specialNote'] ?? '';

    final statusList = data['statusList'] as List<dynamic>? ?? [];
    selectedStatuses = statusList.map((e) => e.toString()).toList();
  }

  // 수정 메서드
  Future<void> updatePlateEntry(BuildContext context, bool mounted, VoidCallback refreshUI) async {
    // ✅ UI 강제: 제출 가드
    if (!_validateBeforeWrite(context)) return;

    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final userName = context.read<UserState>().name;

    isLoading = true;
    refreshUI();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await FirestoreLogger().log('✏️ plate 수정 시작: $plateNumber');

      await _plateRepo.setPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: customStatusController.text.trim(),
        statusList: selectedStatuses,
        createdBy: userName,
      );

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
        periodUnit: selectedPeriodUnit,
        specialNote: specialNote,
        isExtended: isExtended,
      );

      // ✅ 결제는 결제 버튼 클릭 시만 처리됨

      await extendDatesIfNeeded();

      if (mounted) {
        Navigator.of(context).pop();
        showSuccessSnackbar(context, '수정 완료');
        resetForm();
      }

      await FirestoreLogger().log('✅ plate 수정 완료: $plateNumber');
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showFailedSnackbar(context, '수정 실패: ${e.toString()}');
      }
      await FirestoreLogger().log('❌ plate 수정 실패: $e');
    } finally {
      isLoading = false;
      if (mounted) refreshUI();
    }
  }

  // 등록 메서드
  Future<void> submitPlateEntry(BuildContext context, bool mounted, VoidCallback refreshUI) async {
    // ✅ UI 강제: 제출 가드
    if (!_validateBeforeWrite(context)) return;

    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final userName = context.read<UserState>().name;

    selectedBillType = '정기';
    isLoading = true;
    refreshUI();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await FirestoreLogger().log('🚀 plate 등록 시작: $plateNumber');

      await _plateRepo.setPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: customStatusController.text.trim(),
        statusList: selectedStatuses,
        createdBy: userName,
      );

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
        periodUnit: selectedPeriodUnit,
        specialNote: specialNote,
        isExtended: isExtended,
      );

      // ✅ 결제는 사용자가 결제 버튼을 눌렀을 때만 처리 (여기서는 호출하지 않음)

      if (mounted) {
        Navigator.of(context).pop();
        showSuccessSnackbar(context, '차량 정보 등록 완료');
        resetForm();
      }

      await FirestoreLogger().log('🎉 plate 등록 완료: $plateNumber');
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showFailedSnackbar(context, '등록 실패: ${e.toString()}');
      }
      await FirestoreLogger().log('❌ plate 등록 실패: $e');
    } finally {
      isLoading = false;
      if (mounted) refreshUI();
    }
  }
}
