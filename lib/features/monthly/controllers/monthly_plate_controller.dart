import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../../../shared/plate/domain/repositories/plate_repository.dart';
import '../application/monthly_area_resolver.dart';
import '../application/monthly_date_range_calculator.dart';

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

  late TextEditingController activeController;

  bool showKeypad = true;
  bool isLoading = false;
  bool isLocationSelected = false;
  bool isThreeDigit = true;
  bool isEditMode = false;
  bool isExtended = false;

  String dropdownValue = '전국';
  String selectedBillType = '정기';
  String specialNote = '';
  String? fetchedCustomStatus;
  String? selectedRegularType;
  String selectedPeriodUnit = '월';
  String? docIdToEdit;

  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;

  List<String> statuses = [];
  List<bool> isSelected = [];
  List<String> selectedStatuses = [];
  List<String> fetchedStatusList = [];
  final List<XFile> capturedImages = [];

  TextEditingController? regularAmountController;
  TextEditingController? regularDurationController;

  bool _listenersAdded = false;

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

  bool get hasStatusOrMemo =>
      customStatusController.text.trim().isNotEmpty || selectedStatuses.isNotEmpty;

  PlateRepository _plateRepository(BuildContext context) {
    return context.read<PlateRepository>();
  }

  String currentArea(BuildContext context) {
    return MonthlyAreaResolver.readCurrentArea(context);
  }

  void _showMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  bool _validateBeforeWrite(BuildContext context) {
    if (!isInputValid()) {
      _showMessage(context, '차량번호를 완성해주세요.');
      return false;
    }

    final area = currentArea(context);
    if (area.isEmpty) {
      _showMessage(context, '현재 지점을 먼저 선택해주세요.');
      return false;
    }

    final name = nameController?.text.trim() ?? '';
    if (name.isEmpty) {
      _showMessage(context, '정기 정산 이름을 입력해주세요.');
      return false;
    }

    if ((selectedRegularType ?? '').trim().isEmpty) {
      _showMessage(context, '주차 타입을 선택해주세요.');
      return false;
    }

    final amount = int.tryParse(amountController?.text.trim() ?? '');
    if (amount == null || amount <= 0) {
      _showMessage(context, '정기 요금은 1원 이상이어야 합니다.');
      return false;
    }

    final duration = int.tryParse(durationController?.text.trim() ?? '');
    if (duration == null || duration <= 0) {
      _showMessage(context, '기간은 1 이상이어야 합니다.');
      return false;
    }

    final start = MonthlyDateRangeCalculator.parseStrict(
      startDateController?.text.trim() ?? '',
    );
    final end = MonthlyDateRangeCalculator.parseStrict(
      endDateController?.text.trim() ?? '',
    );

    if (start == null) {
      _showMessage(context, '시작일을 YYYY-MM-DD 형식으로 선택해주세요.');
      return false;
    }

    if (end == null) {
      _showMessage(context, '종료일을 YYYY-MM-DD 형식으로 선택해주세요.');
      return false;
    }

    if (start.isAfter(end)) {
      _showMessage(context, '종료일은 시작일보다 빠를 수 없습니다.');
      return false;
    }

    return true;
  }

  bool isInputValid() {
    final frontLen = controllerFrontDigit.text.length;
    final frontOk = frontLen == 2 || frontLen == 3;
    return frontOk &&
        controllerMidDigit.text.length == 1 &&
        controllerBackDigit.text.length == 4;
  }

  String _extractPlateFromDocId(String docId) {
    return docId.split('_').first;
  }

  String formatDate(DateTime date) {
    return MonthlyDateRangeCalculator.format(date);
  }

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
    selectedBillType = '정기';
    regularAmountController?.clear();
    regularDurationController?.clear();
    nameController?.clear();
    amountController?.clear();
    durationController?.clear();
    startDateController?.clear();
    endDateController?.clear();
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

  void updateEndDateFromDuration() {
    final start = MonthlyDateRangeCalculator.parseStrict(
      startDateController?.text.trim() ?? '',
    );
    final duration = int.tryParse(durationController?.text.trim() ?? '');
    if (start == null || duration == null || duration <= 0) return;
    final end = MonthlyDateRangeCalculator.calculateEndDate(
      startDate: start,
      duration: duration,
      periodUnit: selectedPeriodUnit,
    );
    endDateController?.text = formatDate(end);
  }

  DateTime? previewExtendedStartDate() {
    final currentEnd = MonthlyDateRangeCalculator.parseStrict(
      endDateController?.text.trim() ?? '',
    );
    if (currentEnd == null) return null;
    return MonthlyDateRangeCalculator.calculateNextStartDate(currentEnd);
  }

  DateTime? previewExtendedEndDate() {
    final currentEnd = MonthlyDateRangeCalculator.parseStrict(
      endDateController?.text.trim() ?? '',
    );
    final duration = int.tryParse(durationController?.text.trim() ?? '');
    if (currentEnd == null || duration == null || duration <= 0) return null;
    return MonthlyDateRangeCalculator.calculateNextEndDate(
      currentEndDate: currentEnd,
      duration: duration,
      periodUnit: selectedPeriodUnit,
    );
  }

  Future<void> extendDatesIfNeeded() async {
    if (!isExtended) return;
    final nextStart = previewExtendedStartDate();
    final nextEnd = previewExtendedEndDate();
    if (nextStart == null || nextEnd == null) return;
    startDateController?.text = formatDate(nextStart);
    endDateController?.text = formatDate(nextEnd);
  }

  bool validatePaymentBeforeWrite(BuildContext context) {
    if (!isInputValid()) {
      _showMessage(context, '차량번호를 완성해주세요.');
      return false;
    }

    final area = currentArea(context);
    if (area.isEmpty) {
      _showMessage(context, '현재 지점을 먼저 선택해주세요.');
      return false;
    }

    final amount = int.tryParse(amountController?.text.trim() ?? '');
    if (amount == null || amount <= 0) {
      _showMessage(context, '결제 금액은 1원 이상이어야 합니다.');
      return false;
    }

    if (isExtended) {
      final nextStart = previewExtendedStartDate();
      final nextEnd = previewExtendedEndDate();
      if (nextStart == null || nextEnd == null) {
        _showMessage(context, '연장할 기간을 계산할 수 없습니다. 기간 정보를 확인해주세요.');
        return false;
      }
    }

    return true;
  }

  Future<void> processPayment(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = currentArea(context);
    final userName = context.read<UserState>().name;
    String? nextStartText;
    String? nextEndText;

    if (isExtended) {
      final nextStart = previewExtendedStartDate();
      final nextEnd = previewExtendedEndDate();
      if (nextStart != null && nextEnd != null) {
        nextStartText = formatDate(nextStart);
        nextEndText = formatDate(nextEnd);
      }
    }

    await _plateRepository(context).recordMonthlyPaymentAndMaybeExtend(
      plateNumber: plateNumber,
      area: area,
      paidBy: userName,
      amount: int.tryParse(amountController?.text.trim() ?? '') ?? 0,
      note: specialNote,
      extended: isExtended,
      startDate: nextStartText,
      endDate: nextEndText,
      extendedBy: isExtended ? userName : null,
    );

    if (isExtended && nextStartText != null && nextEndText != null) {
      startDateController?.text = nextStartText;
      endDateController?.text = nextEndText;
    }
  }

  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = currentArea(context);
    final userName = context.read<UserState>().name;

    await _plateRepository(context).clearMonthlyMemoAndStatusWithAudit(
      plateNumber: plateNumber,
      area: area,
      clearedBy: userName,
    );

    customStatusController.clear();
    selectedStatuses.clear();
    fetchedCustomStatus = null;
    fetchedStatusList = [];
    isSelected = List.generate(statuses.length, (_) => false);
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
      isThreeDigit = front.length == 3;
      controllerFrontDigit.text = front;
      controllerMidDigit.text = mid;
      controllerBackDigit.text = back;
    }

    dropdownValue = (data['region'] ?? '전국').toString();
    nameController?.text = (data['countType'] ?? '').toString();
    amountController?.text = (data['regularAmount'] ?? '').toString();
    durationController?.text = (data['regularDurationHours'] ?? '').toString();
    selectedRegularType = (data['regularType'] ?? '').toString();
    selectedPeriodUnit = (data['periodUnit'] ?? '월').toString();
    startDateController?.text = (data['startDate'] ?? '').toString();
    endDateController?.text = (data['endDate'] ?? '').toString();
    customStatusController.text = (data['customStatus'] ?? '').toString();
    specialNote = (data['specialNote'] ?? '').toString();

    final statusList = data['statusList'] as List<dynamic>? ?? [];
    selectedStatuses = statusList.map((e) => e.toString()).toList();
  }

  Future<void> updatePlateEntry(
    BuildContext context,
    VoidCallback refreshUI,
  ) async {
    if (!_validateBeforeWrite(context)) return;

    final nav = Navigator.of(context, rootNavigator: true);
    final plateNumber = buildPlateNumber();
    final area = currentArea(context);
    final userName = context.read<UserState>().name;

    isLoading = true;
    refreshUI();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _plateRepository(context).setMonthlyPlateStatus(
        plateNumber: plateNumber,
        area: area,
        region: dropdownValue.trim().isEmpty ? '전국' : dropdownValue.trim(),
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
      _showMessage(context, '정기 주차 정보가 수정되었습니다.');
      if (nav.canPop()) nav.pop();
      if (nav.canPop()) nav.pop();
      resetForm();
    } catch (e) {
      if (!context.mounted) return;
      if (nav.canPop()) nav.pop();
      _showMessage(context, '수정에 실패했습니다. 다시 시도해주세요.');
      debugPrint('월주차 수정 실패: ${e.toString()}');
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
    final area = currentArea(context);
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
      await _plateRepository(context).setMonthlyPlateStatus(
        plateNumber: plateNumber,
        area: area,
        region: dropdownValue.trim().isEmpty ? '전국' : dropdownValue.trim(),
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
      _showMessage(context, '정기 주차가 등록되었습니다.');
      if (nav.canPop()) nav.pop();
      if (nav.canPop()) nav.pop();
      resetForm();
    } catch (e) {
      if (!context.mounted) return;
      if (nav.canPop()) nav.pop();
      _showMessage(context, '등록에 실패했습니다. 다시 시도해주세요.');
      debugPrint('월주차 등록 실패: ${e.toString()}');
    } finally {
      isLoading = false;
      if (context.mounted) refreshUI();
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
}
