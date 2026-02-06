import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../../../../utils/snackbar_helper.dart';

import '../../../../../repositories/plate_repo_services/firestore_plate_repository.dart';
import '../../../../../states/user/user_state.dart';
import '../../../../../states/area/area_state.dart';

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
  final TextEditingController? nameController; // countType
  final TextEditingController? amountController; // regularAmount
  final TextEditingController? durationController; // duration(숫자)
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

  bool get hasStatusOrMemo =>
      customStatusController.text.trim().isNotEmpty || selectedStatuses.isNotEmpty;

  /// 제출 전 가드(등록/수정)
  bool _validateBeforeWrite(BuildContext context) {
    if (!isInputValid()) {
      showFailedSnackbar(context, '번호판을 올바르게 입력해주세요.');
      return false;
    }

    final startTxt = startDateController?.text.trim() ?? '';
    final durTxt = durationController?.text.trim() ?? '';
    final dur = int.tryParse(durTxt);

    if (startTxt.isEmpty || durTxt.isEmpty || dur == null || dur <= 0) {
      showFailedSnackbar(context, '기간 정보를 올바르게 입력해주세요.');
      return false;
    }

    // 포함형 기준 start<=end 체크
    final start = DateTime.tryParse(startTxt);
    final end = DateTime.tryParse(endDateController?.text.trim() ?? '');
    if (start == null || end == null || start.isAfter(end)) {
      showFailedSnackbar(context, '시작/종료일을 확인해주세요.');
      return false;
    }

    return true;
  }

  /// 앞자리(2/3자리), 중간(한글 1자), 뒷자리(4자리)
  bool isInputValid() {
    final frontLen = controllerFrontDigit.text.length;
    final frontOk = (frontLen == 2 || frontLen == 3);
    return frontOk &&
        controllerMidDigit.text.length == 1 &&
        controllerBackDigit.text.length == 4;
  }

  /// "plateNumber_area" 형태의 문서 ID에서 plateNumber만 추출
  String _extractPlateFromDocId(String docId) {
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

  /// ✅ 포함형(inclusive) 종료일 계산
  /// - 일: start + (dur-1)
  /// - 주: start + (dur*7-1)
  /// - 월: addMonths(start, dur) - 1day
  DateTime _calcInclusiveEnd(DateTime start, int dur, String unit) {
    if (dur <= 0) return start;

    switch (unit) {
      case '일':
        return start.add(Duration(days: dur - 1));
      case '주':
        return start.add(Duration(days: dur * 7 - 1));
      case '월':
      default:
        final exclusive = _addMonths(start, dur);
        return exclusive.subtract(const Duration(days: 1));
    }
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

    final end = _calcInclusiveEnd(start, dur, selectedPeriodUnit);
    endDateController?.text = formatDate(end);
  }

  /// ✅ 연장 시 날짜 겹침 방지
  /// - 새 시작일 = 기존 종료일 + 1일
  /// - 새 종료일 = 새 시작일 기준 포함형 규칙 적용
  Future<void> extendDatesIfNeeded() async {
    if (!isExtended) return;

    final currentEnd = DateTime.tryParse(endDateController?.text.trim() ?? '');
    if (currentEnd == null) return;

    final dur = int.tryParse(durationController?.text.trim() ?? '');
    if (dur == null || dur <= 0) return;

    final newStart = currentEnd.add(const Duration(days: 1));
    final newEnd = _calcInclusiveEnd(newStart, dur, selectedPeriodUnit);

    startDateController?.text = formatDate(newStart);
    endDateController?.text = formatDate(newEnd);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ✅ 결제 전용: 검증 + 처리
  // ─────────────────────────────────────────────────────────────────────────────

  bool validatePaymentBeforeWrite(BuildContext context) {
    if (!isInputValid()) {
      showFailedSnackbar(context, '번호판을 먼저 정확히 입력하세요.');
      return false;
    }

    final amount = int.tryParse(amountController?.text.trim() ?? '');
    if (amount == null || amount <= 0) {
      showFailedSnackbar(context, '결제 금액을 확인해주세요.');
      return false;
    }

    return true;
  }

  Future<void> processPayment(BuildContext context) async {
    await recordPaymentHistory(context);

    if (isExtended) {
      await extendDatesIfNeeded();

      final area = context.read<AreaState>().currentArea;
      final plateNumber = buildPlateNumber();
      final docId = '${plateNumber}_$area';

      await FirebaseFirestore.instance.collection('monthly_plate_status').doc(docId).set(
        {
          'startDate': startDateController?.text.trim() ?? '',
          'endDate': endDateController?.text.trim() ?? '',
          'updatedAt': FieldValue.serverTimestamp(),
          'extendedAt': FieldValue.serverTimestamp(),
          'extendedBy': context.read<UserState>().name,
        },
        SetOptions(merge: true),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Firestore 연동
  // ─────────────────────────────────────────────────────────────────────────────
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

    final docId = '${plateNumber}_$area';

    await FirebaseFirestore.instance.collection('monthly_plate_status').doc(docId).set(
      {'payment_history': FieldValue.arrayUnion([historyEntry])},
      SetOptions(merge: true),
    );
  }

  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final userName = context.read<UserState>().name;

    final docId = '${plateNumber}_$area';
    final ref = FirebaseFirestore.instance.collection('monthly_plate_status').doc(docId);

    try {
      await ref.update({
        'customStatus': '',
        'statusList': <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
        'clearedAt': FieldValue.serverTimestamp(),
        'clearedBy': userName,
      });

      customStatusController.clear();
      selectedStatuses.clear();
      fetchedCustomStatus = null;
      fetchedStatusList = [];
      isSelected = List.generate(statuses.length, (_) => false);

      if (!context.mounted) return;
      showSuccessSnackbar(context, '메모/상태가 초기화되었습니다.');
    } on FirebaseException catch (e) {
      if (!context.mounted) return;

      if (e.code == 'not-found') {
        showFailedSnackbar(context, '대상 문서가 없습니다. 먼저 등록 후 시도해주세요.');
        return;
      }
      showFailedSnackbar(context, '초기화 실패: ${e.message ?? e.code}');
      rethrow;
    } catch (e) {
      if (!context.mounted) return;
      showFailedSnackbar(context, '초기화 실패: $e');
      rethrow;
    }
  }

  Future<void> loadExistingData(
      Map<String, dynamic> data, {
        required String docId,
      }) async {
    isEditMode = true;
    docIdToEdit = docId;

    final plate = _extractPlateFromDocId(docId);
    final parts = plate.split('-');
    if (parts.length == 3) {
      final front = parts[0];
      final mid = parts[1];
      final back = parts[2];

      isThreeDigit = (front.length == 3);

      controllerFrontDigit.text = front;
      controllerMidDigit.text = mid;
      controllerBackDigit.text = back;
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
  // 등록/수정
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> updatePlateEntry(
      BuildContext context,
      VoidCallback refreshUI,
      ) async {
    if (!_validateBeforeWrite(context)) return;

    final nav = Navigator.of(context, rootNavigator: true);

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

      if (!context.mounted) return;

      if (nav.canPop()) nav.pop();
      showSuccessSnackbar(context, '수정 완료');
      resetForm();
    } catch (e) {
      if (!context.mounted) return;

      if (nav.canPop()) nav.pop();
      showFailedSnackbar(context, '수정 실패: ${e.toString()}');
    } finally {
      isLoading = false;
      if (context.mounted) refreshUI();
    }
  }

  Future<void> submitPlateEntry(
      BuildContext context,
      VoidCallback refreshUI,
      ) async {
    if (!_validateBeforeWrite(context)) return;

    final nav = Navigator.of(context, rootNavigator: true);

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

      if (!context.mounted) return;

      if (nav.canPop()) nav.pop();
      showSuccessSnackbar(context, '차량 정보 등록 완료');
      resetForm();
    } catch (e) {
      if (!context.mounted) return;

      if (nav.canPop()) nav.pop();
      showFailedSnackbar(context, '등록 실패: ${e.toString()}');
    } finally {
      isLoading = false;
      if (context.mounted) refreshUI();
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
