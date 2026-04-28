import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../dev/application/area_state.dart';

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

  String dropdownValue = '전국';
  String selectedBillType = '정기';

  String specialNote = '';
  bool isExtended = false;

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

  bool isEditMode = false;
  String? docIdToEdit;

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

  bool get hasStatusOrMemo =>
      customStatusController.text.trim().isNotEmpty ||
      selectedStatuses.isNotEmpty;

  PlateRepository _plateRepository(BuildContext context) {
    return context.read<PlateRepository>();
  }

  bool _validateBeforeWrite(BuildContext context) {
    if (!isInputValid()) {
      return false;
    }

    final startTxt = startDateController?.text.trim() ?? '';
    final durTxt = durationController?.text.trim() ?? '';
    final dur = int.tryParse(durTxt);

    if (startTxt.isEmpty || durTxt.isEmpty || dur == null || dur <= 0) {
      return false;
    }

    final start = DateTime.tryParse(startTxt);
    final end = DateTime.tryParse(endDateController?.text.trim() ?? '');
    if (start == null || end == null || start.isAfter(end)) {
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
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  DateTime _addMonths(DateTime dt, int months) {
    final y = dt.year + ((dt.month - 1 + months) ~/ 12);
    final m = ((dt.month - 1 + months) % 12) + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    final d = dt.day > lastDay ? lastDay : dt.day;
    return DateTime(y, m, d);
  }

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
    final startText = startDateController?.text.trim();
    final durationText = durationController?.text.trim();
    if (startText == null || durationText == null) return;

    final start = DateTime.tryParse(startText);
    final dur = int.tryParse(durationText);
    if (start == null || dur == null || dur <= 0) return;

    final end = _calcInclusiveEnd(start, dur, selectedPeriodUnit);
    endDateController?.text = formatDate(end);
  }

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

  bool validatePaymentBeforeWrite(BuildContext context) {
    if (!isInputValid()) {
      return false;
    }

    final amount = int.tryParse(amountController?.text.trim() ?? '');
    if (amount == null || amount <= 0) {
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

      await _plateRepository(context).extendMonthlyDateRange(
        plateNumber: plateNumber,
        area: area,
        startDate: startDateController?.text.trim() ?? '',
        endDate: endDateController?.text.trim() ?? '',
        extendedBy: context.read<UserState>().name,
      );
    }
  }

  Future<void> recordPaymentHistory(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final userName = context.read<UserState>().name;

    await _plateRepository(context).recordMonthlyPayment(
      plateNumber: plateNumber,
      area: area,
      paidBy: userName,
      amount: int.tryParse(amountController?.text.trim() ?? '') ?? 0,
      note: specialNote,
      extended: isExtended,
    );
  }

  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
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
      await _plateRepository(context).setMonthlyPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: customStatusController.text.trim(),
        statusList: selectedStatuses,
        createdBy: userName,
        countType: nameController?.text.trim() ?? '',
        regularAmount: int.tryParse(amountController?.text.trim() ?? '') ?? 0,
        regularDurationHours:
            int.tryParse(durationController?.text.trim() ?? '') ?? 0,
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
      resetForm();
    } catch (e) {
      if (!context.mounted) return;

      if (nav.canPop()) nav.pop();
      debugPrint('수정 실패: ${e.toString()}');
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
      await _plateRepository(context).setMonthlyPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: customStatusController.text.trim(),
        statusList: selectedStatuses,
        createdBy: userName,
        countType: nameController?.text.trim() ?? '',
        regularAmount: int.tryParse(amountController?.text.trim() ?? '') ?? 0,
        regularDurationHours:
            int.tryParse(durationController?.text.trim() ?? '') ?? 0,
        regularType: selectedRegularType ?? '정기 주차',
        startDate: startDateController?.text.trim() ?? '',
        endDate: endDateController?.text.trim() ?? '',
        periodUnit: selectedPeriodUnit,
        specialNote: specialNote,
        isExtended: isExtended,
      );

      if (!context.mounted) return;

      if (nav.canPop()) nav.pop();
      resetForm();
    } catch (e) {
      if (!context.mounted) return;

      if (nav.canPop()) nav.pop();
      debugPrint('등록 실패: ${e.toString()}');
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
