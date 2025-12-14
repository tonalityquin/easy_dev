import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../../utils/snackbar_helper.dart';
import 'utils/lite_input_plate_service.dart';

import '../../../states/bill/bill_state.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../repositories/plate_repo_services/firestore_plate_repository.dart';

class LiteInputPlateController {
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

  LiteInputPlateController() {
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
    final validFront =
    isThreeDigit ? controllerFrontDigit.text.length == 3 : controllerFrontDigit.text.length == 2;
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

    // 정기인데 선택값이 비어있으면 countTypeController를 폴백으로 반영
    if (selectedBillType == '정기' && (selectedBill == null || selectedBill!.trim().isEmpty)) {
      final ct = countTypeController.text.trim();
      if (ct.isNotEmpty) selectedBill = ct;
    }

    if (hasAnyBill && selectedBill == null && selectedBillType != '정기') {
      showFailedSnackbar(context, '정산 유형을 선택해주세요');
      return;
    }

    bool didPopScreen = false;

    isLoading = true;
    refreshUI();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final uploadedUrls = await LiteInputPlateService.uploadCapturedImages(
        capturedImages,
        plateNumber,
        area,
        userName,
        division,
      );

      final wasSuccessful = await LiteInputPlateService.registerPlateEntry(
        context: context,
        plateNumber: plateNumber,
        location: locationController.text,
        isLocationSelected: isLocationSelected,
        imageUrls: uploadedUrls,
        selectedBill: selectedBill,
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

      // ✅ async gap 이후, BuildContext 안전성 확인
      if (!context.mounted) return;

      // 1) 로딩 다이얼로그 닫기 (showDialog는 보통 rootNavigator에 붙음)
      final rootNav = Navigator.of(context, rootNavigator: true);
      if (rootNav.canPop()) rootNav.pop();

      if (!wasSuccessful) {
        // ✅ 실패 시: InputPlateScreen에 머물기
        // (registerPlateEntry 내부에서 이미 안내하는 경우가 있어도 안전하게 한 번 더 안내)
        showFailedSnackbar(context, '동일한 차량 번호가 있습니다.');
        return;
      }

      // 2) 등록 성공 이후: plate_status 저장은 "부가 작업"으로 분리
      Object? plateStatusError;
      try {
        await _plateRepo.setPlateStatus(
          plateNumber: plateNumber,
          area: area,
          customStatus: customStatusController.text.trim(),
          statusList: selectedStatuses,
          createdBy: userName,
        );
      } catch (e) {
        plateStatusError = e;
        debugPrint('[submitPlateEntry] setPlateStatus failed: $e');
      }

      if (!context.mounted) return;

      // 3) 성공 스낵바
      showSuccessSnackbar(context, '차량 정보 등록 완료');

      // 4) plate_status만 실패한 경우 경고(등록 성공은 유지)
      if (plateStatusError != null) {
        showSelectedSnackbar(context, '등록은 완료되었지만 메모/상태 저장에 실패했습니다.');
      }

      // 5) ✅ 성공 시: TypePage로 복귀 (InputPlateScreen pop)
      didPopScreen = true;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!context.mounted) return;

      // 로딩 다이얼로그 닫기
      final rootNav = Navigator.of(context, rootNavigator: true);
      if (rootNav.canPop()) rootNav.pop();

      // ✅ 예외 발생 시: 화면 유지
      showFailedSnackbar(context, '등록 실패: ${e.toString()}');
    } finally {
      isLoading = false;
      if (context.mounted && !didPopScreen) {
        refreshUI();
      }
    }
  }
}
