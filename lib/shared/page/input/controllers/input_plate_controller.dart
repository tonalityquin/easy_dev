import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/payment/applications/bill_state.dart';
import '../../../../features/plate/domain/repositories/ocr_learning_repository.dart';
import '../../../../features/plate/domain/repositories/plate_repository.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../widgets/dialog/status_dialog_package/action_trace_dialog.dart';
import '../../../../widgets/dialog/status_dialog_package/status_dialog.dart';
import '../application/input_plate_service.dart';

class InputPlateController {
  final bool isMinorMode;

  String? ocrSessionId;
  bool _suppressOcrEditCount = false;

  int ocrEditFrontCnt = 0;
  int ocrEditMidCnt = 0;
  int ocrEditBackCnt = 0;

  String _lastFront = '';
  String _lastMid = '';
  String _lastBack = '';

  final TextEditingController controllerFrontDigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController customStatusController = TextEditingController();

  final TextEditingController countTypeController = TextEditingController();

  bool showKeypad = true;
  bool isLoading = false;
  bool isLocationSelected = false;
  String dropdownValue = '전국';

  String selectedBillType = '변동';
  String? selectedBill;

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

  InputPlateController({this.isMinorMode = false}) {
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

  void _handleInputChange() {
    if (ocrSessionId == null || _suppressOcrEditCount) {
      _lastFront = controllerFrontDigit.text;
      _lastMid = controllerMidDigit.text;
      _lastBack = controllerBackDigit.text;
      return;
    }

    final f = controllerFrontDigit.text;
    final m = controllerMidDigit.text;
    final b = controllerBackDigit.text;

    if (f != _lastFront) {
      ocrEditFrontCnt++;
      _lastFront = f;
    }
    if (m != _lastMid) {
      ocrEditMidCnt++;
      _lastMid = m;
    }
    if (b != _lastBack) {
      ocrEditBackCnt++;
      _lastBack = b;
    }
  }

  void setActiveController(TextEditingController controller) {
    activeController = controller;
    showKeypad = true;
  }

  void suppressOcrEditCount(bool v) {
    _suppressOcrEditCount = v;
    if (v) {
      _lastFront = controllerFrontDigit.text;
      _lastMid = controllerMidDigit.text;
      _lastBack = controllerBackDigit.text;
    }
  }

  void bindOcrSession(String sessionId) {
    ocrSessionId = sessionId;
    ocrEditFrontCnt = 0;
    ocrEditMidCnt = 0;
    ocrEditBackCnt = 0;
    _lastFront = controllerFrontDigit.text;
    _lastMid = controllerMidDigit.text;
    _lastBack = controllerBackDigit.text;
  }

  void clearOcrSession() {
    ocrSessionId = null;
    ocrEditFrontCnt = 0;
    ocrEditMidCnt = 0;
    ocrEditBackCnt = 0;
    _lastFront = controllerFrontDigit.text;
    _lastMid = controllerMidDigit.text;
    _lastBack = controllerBackDigit.text;
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
    clearOcrSession();
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

  PlateRepository _readPlateRepository(BuildContext context) {
    return context.read<PlateRepository>();
  }

  String buildPlateNumber() {
    return '${controllerFrontDigit.text}-${controllerMidDigit.text}-${controllerBackDigit.text}';
  }

  bool isInputValid() {
    final validFront = isThreeDigit
        ? controllerFrontDigit.text.length == 3
        : controllerFrontDigit.text.length == 2;
    return validFront &&
        controllerMidDigit.text.length == 1 &&
        controllerBackDigit.text.length == 4;
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
    final plateRepo = _readPlateRepository(context);

    final bool isMonthly = selectedBillType == '정기';

    try {
      if (!isMonthly) {
        await plateRepo.deletePlateStatus(plateNumber, area);
      } else {
        await plateRepo.clearMonthlyMemoAndStatus(
          plateNumber: plateNumber,
          area: area,
        );
      }

      fetchedCustomStatus = null;
      fetchedStatusList = [];
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _persistMemoAndStatusAfterEntry({
    required PlateRepository plateRepo,
    required String plateNumber,
    required String area,
    required String userName,
  }) async {
    final bool isMonthly = selectedBillType.trim() == '정기';

    final memo = customStatusController.text.trim();
    final statuses = List<String>.from(selectedStatuses);

    final bool hasAny = memo.isNotEmpty || statuses.isNotEmpty;
    if (!hasAny) return;

    if (!isMonthly) {
      await plateRepo.setPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: memo,
        statusList: statuses,
        createdBy: userName,
      );
      return;
    }

    final String ct = (selectedBill ?? '').trim().isNotEmpty
        ? (selectedBill ?? '').trim()
        : countTypeController.text.trim();

    await plateRepo.upsertMonthlyMemoAndStatus(
      plateNumber: plateNumber,
      area: area,
      createdBy: userName,
      customStatus: memo,
      statusList: statuses,
      countType: ct.isNotEmpty ? ct : null,
    );
  }

  Future<bool> submitPlateEntry(
    BuildContext context,
    VoidCallback refreshUI, {
    ActionTraceController? trace,
  }) async {
    trace?.add('입차 처리 시작');

    final isValid = isInputValid();
    trace?.add('isInputValid=$isValid');
    if (!isValid) {
      trace?.add('중단: 번호판 입력 불완전');
      if (context.mounted) {
        showFailedSnackbar(context, '번호판 입력을 확인해주세요.');
      }
      return false;
    }

    final plateNumber = buildPlateNumber();
    final areaState = context.read<AreaState>();
    final plateRepo = _readPlateRepository(context);
    final area = areaState.currentArea;
    final division = areaState.currentDivision;
    final userName = context.read<UserState>().name;
    final billState = context.read<BillState>();
    final hasAnyBill =
        billState.generalBills.isNotEmpty || billState.regularBills.isNotEmpty;

    trace?.add('plateNumber=$plateNumber');
    trace?.add('area=$area division=$division');
    trace?.add('hasAnyBill=$hasAnyBill');

    final location = locationController.text.trim();
    isLocationSelected = location.isNotEmpty;
    trace?.add('location="$location" isLocationSelected=$isLocationSelected');

    if (!isMinorMode && !isLocationSelected) {
      trace?.add('중단: 주차 위치 미선택');
      if (context.mounted) {
        showFailedSnackbar(context, '주차 위치를 선택해주세요.');
      }
      return false;
    }

    if (selectedBillType == '정기' &&
        (selectedBill == null || selectedBill!.trim().isEmpty)) {
      final ct = countTypeController.text.trim();
      trace?.add('정기 countType="$ct"');
      if (ct.isNotEmpty) {
        selectedBill = ct;
      }
    }

    final normalizedSelectedBill = selectedBill?.trim();
    selectedBill =
        (normalizedSelectedBill == null || normalizedSelectedBill.isEmpty)
            ? null
            : normalizedSelectedBill;

    trace?.add(
      'selectedBillType=$selectedBillType selectedBill=${selectedBill ?? ''}',
    );

    if (hasAnyBill &&
        (selectedBill == null || selectedBill!.isEmpty) &&
        selectedBillType != '정기') {
      trace?.add('중단: selectedBill 누락');
      if (context.mounted) {
        showFailedSnackbar(context, '정산 유형을 선택해주세요.');
      }
      return false;
    }

    isLoading = true;
    refreshUI();

    try {
      trace?.add('사진 업로드 시작');
      final uploadResult = await InputPlateService.uploadCapturedImages(
        capturedImages,
        plateNumber,
        area,
        userName,
        division,
      );
      trace?.add(
        '사진 업로드 완료 uploaded=${uploadResult.uploadedUrls.length} failed=${uploadResult.failedCount}',
      );

      if (context.mounted && uploadResult.hasFailure && trace == null) {
        await StatusDialog.showFailure(
          context,
          title: StatusDialog.photoSaveFailed,
        );
      }

      trace?.add('입차 등록 시작');
      final wasSuccessful = await InputPlateService.registerPlateEntry(
        context: context,
        plateNumber: plateNumber,
        location: isLocationSelected ? location : '',
        isLocationSelected: isLocationSelected,
        imageUrls: uploadResult.uploadedUrls,
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
      trace?.add('입차 등록 결과=$wasSuccessful');

      if (!context.mounted) {
        trace?.add('중단: context unmounted after register');
        return false;
      }

      if (!wasSuccessful) {
        trace?.add('중단: registerPlateEntry returned false');
        return false;
      }

      final sid = ocrSessionId;
      if (sid != null && sid.isNotEmpty) {
        try {
          trace?.add('OCR 학습 커밋 시작');
          await OcrLearningRepository.instance.commit(
            sessionId: sid,
            finalPlate: plateNumber,
            front: controllerFrontDigit.text,
            mid: controllerMidDigit.text,
            back: controllerBackDigit.text,
            editFrontCnt: ocrEditFrontCnt,
            editMidCnt: ocrEditMidCnt,
            editBackCnt: ocrEditBackCnt,
          );
          clearOcrSession();
          trace?.add('OCR 학습 커밋 완료');
        } catch (e) {
          trace?.add('OCR 학습 커밋 실패: $e');
          debugPrint('[submitPlateEntry] learning commit failed: $e');
        }
      }

      try {
        trace?.add('상태/메모 저장 시작');
        await _persistMemoAndStatusAfterEntry(
          plateRepo: plateRepo,
          plateNumber: plateNumber,
          area: area,
          userName: userName,
        );
        trace?.add('상태/메모 저장 완료');
      } catch (e) {
        trace?.add('상태/메모 저장 실패: $e');
        debugPrint('[submitPlateEntry] persist memo/status failed: $e');
      }

      trace?.add('입차 처리 성공');
      return true;
    } catch (e, st) {
      trace?.add('예외 발생: $e');
      final compactStack = st
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(6)
          .join(' | ');
      if (compactStack.isNotEmpty) {
        trace?.add(compactStack);
      }
      if (context.mounted) {
        showFailedSnackbar(context, '입차 처리 실패: $e');
      }
      return false;
    } finally {
      isLoading = false;
      if (context.mounted) {
        refreshUI();
      }
    }
  }
}
