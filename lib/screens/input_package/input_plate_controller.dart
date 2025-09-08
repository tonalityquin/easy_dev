import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_helper.dart';
import 'utils/input_plate_service.dart';

import '../../states/bill/bill_state.dart';
import '../../states/user/user_state.dart';
import '../../states/area/area_state.dart';
import '../../repositories/plate_repo_services/firestore_plate_repository.dart';

class InputPlateController {
  final TextEditingController controllerFrontDigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController customStatusController = TextEditingController();

  final TextEditingController countTypeController = TextEditingController();

  final FirestorePlateRepository _plateRepo = FirestorePlateRepository();

  bool showKeypad = true;
  bool isLoading = false;
  bool isLocationSelected = false;
  String dropdownValue = '전국';

  String selectedBillType = '변동';
  String? selectedBill; // ✅ 공개 필드로 단순화

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
    'इनcheon', // NOTE: If this was unintended, replace with '인천'
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

  InputPlateController() {
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
    selectedBill = null; // ✅ 변경 반영
    selectedBasicStandard = 0;
    selectedBasicAmount = 0;
    selectedAddStandard = 0;
    selectedAddAmount = 0;

    customStatusController.clear();
    countTypeController.clear();

    fetchedCustomStatus = null;
    fetchedStatusList = [];
    isSelected = List.generate(statuses.length, (_) => false);
    isThreeDigit = true;
    selectedBillType = '변동';
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
    countTypeController.dispose();
  }

  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;

    try {
      await _plateRepo.deletePlateStatus(plateNumber, area);
      fetchedCustomStatus = null;
      fetchedStatusList = [];
    } catch (e) {
      rethrow;
    }
  }

  Future<void> submitPlateEntry(
      BuildContext context,
      VoidCallback refreshUI,
      ) async {
    final plateNumber = buildPlateNumber();
    final areaState = context.read<AreaState>();
    final area = areaState.currentArea;
    final division = areaState.currentDivision;
    final userName = context.read<UserState>().name;
    final billState = context.read<BillState>();
    final hasAnyBill = billState.generalBills.isNotEmpty || billState.regularBills.isNotEmpty;

    if (selectedBillType == '정기' && (selectedBill == null || selectedBill!.trim().isEmpty)) {
      final ct = countTypeController.text.trim();
      if (ct.isNotEmpty) selectedBill = ct; // ✅ 변경 반영
    }

    if (hasAnyBill && selectedBill == null && selectedBillType != '정기') {
      // await 전이므로 context 사용 OK
      showFailedSnackbar(context, '정산 유형을 선택해주세요');
      return;
    }

    isLoading = true;
    refreshUI();

    // await 전이므로 context 사용 OK
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final uploadedUrls = await InputPlateService.uploadCapturedImages(
        capturedImages,
        plateNumber,
        area,
        userName,
        division,
      );

      final wasSuccessful = await InputPlateService.registerPlateEntry(
        context: context, // 내부에서 await 후 context를 쓸 가능성이 있다면 그 함수 내부에서도 context.mounted 체크 필요
        plateNumber: plateNumber,
        location: locationController.text,
        isLocationSelected: isLocationSelected,
        imageUrls: uploadedUrls,
        selectedBill: selectedBill, // ✅ 변경 반영
        selectedStatuses: selectedStatuses,
        basicStandard: selectedBasicStandard,
        basicAmount: selectedBasicAmount,
        addStandard: selectedAddStandard,
        addAmount: selectedAddAmount,
        region: dropdownValue,
        customStatus: customStatusController.text.trim().isNotEmpty
            ? customStatusController.text
            : fetchedCustomStatus ?? '',
        selectedBillType: selectedBillType,
      );

      await _plateRepo.setPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: customStatusController.text.trim(),
        statusList: selectedStatuses,
        createdBy: userName,
      );

      // ✅ async gap 이후, BuildContext 안전성 확인
      if (!context.mounted) return;

      Navigator.of(context).pop();
      if (wasSuccessful) {
        showSuccessSnackbar(context, '차량 정보 등록 완료');
        resetForm();
      }
    } catch (e) {
      // ✅ async gap 이후, BuildContext 안전성 확인
      if (!context.mounted) return;

      Navigator.of(context).pop();
      showFailedSnackbar(context, '등록 실패: ${e.toString()}');
    } finally {
      isLoading = false;
      // setState를 내부에서 호출하는 형태의 콜백이라면 context 생존 여부 확인 권장
      if (context.mounted) {
        refreshUI();
      }
    }
  }
}
