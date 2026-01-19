import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../utils/snackbar_helper.dart';
// import '../../../utils/usage/usage_reporter.dart';
import 'utils/minor_input_plate_service.dart';

import '../../../states/bill/bill_state.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../repositories/plate_repo_services/firestore_plate_repository.dart';

class MinorInputPlateController {
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

  MinorInputPlateController() {
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
    selectedBill = null;
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

  /// ✅ 비정기: plate_status 삭제
  /// ✅ 정기: monthly_plate_status는 “문서 삭제” 대신 메모/상태만 비우는 방식으로 안전 처리(필요 시 정책 변경 가능)
  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final docId = '${plateNumber}_$area';

    final bool isMonthly = selectedBillType == '정기';

    try {
      if (!isMonthly) {
        await _plateRepo.deletePlateStatus(plateNumber, area);
      } else {
        await FirebaseFirestore.instance.collection('monthly_plate_status').doc(docId).set(
          {
            'customStatus': '',
            'statusList': <String>[],
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        /* await UsageReporter.instance.report(
          area: (area.isEmpty ? 'unknown' : area),
          action: 'write',
          n: 1,
          source: 'NormalInputPlateController.deleteCustomStatusFromFirestore/monthly_plate_status.doc.set(merge)',
          useSourceOnlyKey: true,
        ); */
      }

      fetchedCustomStatus = null;
      fetchedStatusList = [];
    } catch (e) {
      rethrow;
    }
  }

  /// ✅ 등록 성공 후 메모/상태 저장을 정산 유형에 따라 분기
  /// - 정기: monthly_plate_status (merge upsert)  ★ plate_status 금지
  /// - 비정기: plate_status (기존 repo 메서드 사용)
  Future<void> _persistMemoAndStatusAfterEntry({
    required String plateNumber,
    required String area,
    required String userName,
  }) async {
    final bool isMonthly = selectedBillType.trim() == '정기';
    final docId = '${plateNumber}_$area';

    final memo = customStatusController.text.trim();
    final statuses = List<String>.from(selectedStatuses);

    final bool hasAny = memo.isNotEmpty || statuses.isNotEmpty;
    if (!hasAny) return;

    if (!isMonthly) {
      // ✅ 기존 동작: 비정기만 plate_status 저장
      await _plateRepo.setPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: memo,
        statusList: statuses,
        createdBy: userName,
      );
      return;
    }

    // ✅ 정기(월정기): monthly_plate_status에만 저장 (plate_status 절대 사용하지 않음)
    final String ct = (selectedBill ?? '').trim().isNotEmpty
        ? (selectedBill ?? '').trim()
        : countTypeController.text.trim();

    await FirebaseFirestore.instance.collection('monthly_plate_status').doc(docId).set(
      {
        'customStatus': memo,
        'statusList': statuses,
        'updatedAt': FieldValue.serverTimestamp(),
        'area': area,
        'createdBy': userName,
        'type': '정기',
        if (ct.isNotEmpty) 'countType': ct,
      },
      SetOptions(merge: true),
    );

    /* await UsageReporter.instance.report(
      area: (area.isEmpty ? 'unknown' : area),
      action: 'write',
      n: 1,
      source: 'NormalInputPlateController._persistMemoAndStatusAfterEntry/monthly_plate_status.doc.set(merge)',
      useSourceOnlyKey: true,
    ); */
  }

  Future<void> minorSubmitPlateEntry(
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

    // ✅ Minor 모드도 Service 모드와 동일하게
    // - 위치가 없으면 "입차 요청"(parking_requests)
    // - 위치가 있으면 "입차 완료"(parking_completed)
    // ※ location이 비어 있으면 commonRegisterPlateEntry에서 '미지정'으로 저장됨
    final location = locationController.text.trim();
    isLocationSelected = location.isNotEmpty;

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
      final uploadedUrls = await MinorInputPlateService.uploadCapturedImages(
        capturedImages,
        plateNumber,
        area,
        userName,
        division,
      );

      final wasSuccessful = await MinorInputPlateService.minorRegisterPlateEntry(
        context: context,
        plateNumber: plateNumber,
        location: location,
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
        showFailedSnackbar(context, '동일한 차량 번호가 있습니다.');
        return;
      }

      // 2) ✅ 등록 성공 이후: 메모/상태 저장은 selectedBillType에 따라 분기
      //    - 정기: monthly_plate_status (plate_status 금지)
      //    - 비정기: plate_status
      Object? memoStatusError;
      try {
        await _persistMemoAndStatusAfterEntry(
          plateNumber: plateNumber,
          area: area,
          userName: userName,
        );
      } catch (e) {
        memoStatusError = e;
        debugPrint('[submitPlateEntry] persist memo/status failed: $e');
      }

      if (!context.mounted) return;

      // 3) 성공 스낵바
      showSuccessSnackbar(context, '차량 정보 등록 완료');

      // 4) 메모/상태만 실패한 경우 경고(등록 성공은 유지)
      if (memoStatusError != null) {
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

      showFailedSnackbar(context, '등록 실패: ${e.toString()}');
    } finally {
      isLoading = false;
      if (context.mounted && !didPopScreen) {
        refreshUI();
      }
    }
  }
}
