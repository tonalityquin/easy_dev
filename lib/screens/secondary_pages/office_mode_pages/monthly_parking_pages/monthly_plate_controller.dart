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
  // ─────────────────────────────────────────────────────────────────────────────
  // 입력 컨트롤러
  // ─────────────────────────────────────────────────────────────────────────────
  final TextEditingController controllerFrontDigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();

  final TextEditingController locationController = TextEditingController();
  final TextEditingController customStatusController = TextEditingController();

  // 요금/기간 관련(필요 시 주입)
  final TextEditingController? nameController;      // countType
  final TextEditingController? amountController;    // regularAmount
  final TextEditingController? durationController;  // duration(숫자)
  final TextEditingController? startDateController;
  final TextEditingController? endDateController;

  late TextEditingController activeController;

  // ─────────────────────────────────────────────────────────────────────────────
  // 상태
  // ─────────────────────────────────────────────────────────────────────────────
  bool showKeypad = true;
  bool isLoading = false;
  bool isLocationSelected = false;

  String dropdownValue = '전국';
  String selectedBillType = '정기';

  // 결제 관련
  String specialNote = '';
  bool isExtended = false;

  // 금액/기본/추가 기준 선택(사용처에 따라 확장)
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

  // 지역 목록(불변)
  static const List<String> regions = [
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

  final List<XFile> capturedImages = [];

  TextEditingController? regularAmountController;
  TextEditingController? regularDurationController;
  String? selectedRegularType;
  String selectedPeriodUnit = '월';

  // 수정 상태
  bool isEditMode = false;
  String? docIdToEdit;

  // 내부
  final FirestorePlateRepository _plateRepo = FirestorePlateRepository();
  bool _listenersAdded = false;

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

  // ─────────────────────────────────────────────────────────────────────────────
  // 유틸/검증
  // ─────────────────────────────────────────────────────────────────────────────

  /// 상태 or 메모가 하나 이상 입력되어 있는지
  bool get hasStatusOrMemo =>
      customStatusController.text.trim().isNotEmpty || selectedStatuses.isNotEmpty;

  /// 제출 전 간단 가드(번호판/기간/상태·메모)
  bool _validateBeforeWrite(BuildContext context) {
    if (!isInputValid()) {
      showFailedSnackbar(context, '번호판을 올바르게 입력해주세요.');
      return false;
    }

    // 기간 필수 및 양수 검증
    final startTxt = startDateController?.text.trim() ?? '';
    final durTxt = durationController?.text.trim() ?? '';
    final dur = int.tryParse(durTxt);

    if (startTxt.isEmpty || durTxt.isEmpty || dur == null || dur <= 0) {
      showFailedSnackbar(context, '기간 정보를 올바르게 입력해주세요.');
      return false;
    }

    if (!hasStatusOrMemo) {
      showFailedSnackbar(context, '상태를 선택하거나 메모를 입력해주세요.');
      return false;
    }
    return true;
  }

  /// 앞자리(2/3자리), 중간(한글 1자), 뒷자리(4자리) 유효성
  bool isInputValid() {
    final validFront =
    isThreeDigit ? controllerFrontDigit.text.length == 3 : controllerFrontDigit.text.length == 2;
    return validFront &&
        controllerMidDigit.text.length == 1 &&
        controllerBackDigit.text.length == 4;
  }

  /// "plateNumber_area" 형태의 문서 ID에서 plateNumber만 추출
  String _extractPlateFromDocId(String docId) {
    // ex) "12가-3456_서울" -> "12가-3456"
    return docId.split('_').first;
  }

  /// yyyy-MM-dd
  String formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// 월 단위 정확한 더하기(말일 보정)
  DateTime _addMonths(DateTime dt, int months) {
    final y = dt.year + ((dt.month - 1 + months) ~/ 12);
    final m = ((dt.month - 1 + months) % 12) + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    final d = dt.day > lastDay ? lastDay : dt.day;
    return DateTime(y, m, d);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 리스너
  // ─────────────────────────────────────────────────────────────────────────────
  void _addInputListeners() {
    if (_listenersAdded) return;
    controllerFrontDigit.addListener(_handleInputChange);
    controllerMidDigit.addListener(_handleInputChange);
    controllerBackDigit.addListener(_handleInputChange);
    durationController?.addListener(updateEndDateFromDuration);
    _listenersAdded = true;
  }

  void _removeInputListeners() {
    if (!_listenersAdded) return;
    controllerFrontDigit.removeListener(_handleInputChange);
    controllerMidDigit.removeListener(_handleInputChange);
    controllerBackDigit.removeListener(_handleInputChange);
    durationController?.removeListener(updateEndDateFromDuration);
    _listenersAdded = false;
  }

  void _handleInputChange() {
    // 필요 시 자동 포커스 이동/키패드 전환 등을 구현
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 상태 변경/초기화
  // ─────────────────────────────────────────────────────────────────────────────
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
    selectedBillType = '정기';
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

  // ─────────────────────────────────────────────────────────────────────────────
  // 날짜 계산
  // ─────────────────────────────────────────────────────────────────────────────
  void updateEndDateFromDuration() {
    final startText = startDateController?.text.trim();
    final durationText = durationController?.text.trim();
    if (startText == null || durationText == null) return;

    final start = DateTime.tryParse(startText);
    final dur = int.tryParse(durationText);
    if (start == null || dur == null || dur <= 0) return;

    DateTime end;
    switch (selectedPeriodUnit) {
      case '일':
        end = start.add(Duration(days: dur));
        break;
      case '주':
        end = start.add(Duration(days: dur * 7));
        break;
      case '월':
      default:
        end = _addMonths(start, dur);
        break;
    }
    endDateController?.text = formatDate(end);
  }

  Future<void> extendDatesIfNeeded() async {
    if (!isExtended) return;

    final currentEnd = DateTime.tryParse(endDateController?.text ?? '');
    if (currentEnd == null) return;

    final dur = int.tryParse(durationController?.text.trim() ?? '');
    if (dur == null || dur <= 0) return;

    final newStart = currentEnd;
    DateTime newEnd;
    switch (selectedPeriodUnit) {
      case '일':
        newEnd = currentEnd.add(Duration(days: dur));
        break;
      case '주':
        newEnd = currentEnd.add(Duration(days: dur * 7));
        break;
      case '월':
      default:
        newEnd = _addMonths(currentEnd, dur);
        break;
    }

    startDateController?.text = formatDate(newStart);
    endDateController?.text = formatDate(newEnd);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Firestore 연동
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> recordPaymentHistory(BuildContext context) async {
    // 기존 UI 코드 호환을 위해 context를 유지
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
      await FirebaseFirestore.instance
          .collection('plate_status')
          .doc(docId)
          .set(
        {'payment_history': FieldValue.arrayUnion([historyEntry])},
        SetOptions(merge: true),
      );
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

  /// 기존 문서 데이터 로딩(편집 진입 시)
  Future<void> loadExistingData(
      Map<String, dynamic> data, {
        required String docId,
      }) async {
    isEditMode = true;
    docIdToEdit = docId;

    final plate = _extractPlateFromDocId(docId);
    final parts = plate.split('-'); // [앞, 한글, 뒤]
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

  // ─────────────────────────────────────────────────────────────────────────────
  // 등록/수정 (UI와의 호환 유지)
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> updatePlateEntry(
      BuildContext context,
      bool mounted,
      VoidCallback refreshUI,
      ) async {
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

      await extendDatesIfNeeded();

      if (mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
        showSuccessSnackbar(context, '수정 완료');
        resetForm();
      }

      await FirestoreLogger().log('✅ plate 수정 완료: $plateNumber');
    } catch (e) {
      if (mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
        showFailedSnackbar(context, '수정 실패: ${e.toString()}');
      }
      await FirestoreLogger().log('❌ plate 수정 실패: $e');
    } finally {
      isLoading = false;
      if (mounted) refreshUI();
    }
  }

  Future<void> submitPlateEntry(
      BuildContext context,
      bool mounted,
      VoidCallback refreshUI,
      ) async {
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

      if (mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
        showSuccessSnackbar(context, '차량 정보 등록 완료');
        resetForm();
      }

      await FirestoreLogger().log('🎉 plate 등록 완료: $plateNumber');
    } catch (e) {
      if (mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
        showFailedSnackbar(context, '등록 실패: ${e.toString()}');
      }
      await FirestoreLogger().log('❌ plate 등록 실패: $e');
    } finally {
      isLoading = false;
      if (mounted) refreshUI();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 수명주기
  // ─────────────────────────────────────────────────────────────────────────────
  void dispose() {
    _removeInputListeners();
    controllerFrontDigit.dispose();
    controllerMidDigit.dispose();
    controllerBackDigit.dispose();
    locationController.dispose();
    customStatusController.dispose();
  }
}
