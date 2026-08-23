import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../../../app/models/capability.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/payment/applications/bill_state.dart';
import '../../../../features/sector/applications/sector_state.dart';
import '../../../../features/sector/domain/models/sector_model.dart';
import '../../../plate/domain/models/plate_status_draft.dart';
import '../../../plate/domain/models/plate_status_lookup_result.dart';
import '../../../plate/domain/repositories/plate_repository.dart';
import '../../../plate/widgets/action_trace_dialog.dart';
import '../application/input_plate_service.dart';
import '../domain/repositories/ocr_learning_repository.dart';

class _SectorEntryResolution {
  const _SectorEntryResolution({
    required this.proceed,
    this.sector,
  });

  final bool proceed;
  final SectorModel? sector;
}

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

  String? selectedManufacturerName;
  String? selectedModelName;
  String? selectedSectorId;
  String? selectedSectorName;
  String? priority1SlotKey;
  String? priority2SlotKey;
  String? priority3SlotKey;

  List<String> get selectedParkingPriorities {
    return <String>[
      if (priority1SlotKey != null &&
          priority1SlotKey!.trim().isNotEmpty)
        priority1SlotKey!.trim(),
      if (priority2SlotKey != null &&
          priority2SlotKey!.trim().isNotEmpty)
        priority2SlotKey!.trim(),
      if (priority3SlotKey != null &&
          priority3SlotKey!.trim().isNotEmpty)
        priority3SlotKey!.trim(),
    ];
  }

  bool statusWriteRequested = false;
  bool statusDeletionRequested = false;
  bool statusEditedByUser = false;
  PlateStatusLookupState statusLookupState = PlateStatusLookupState.idle;
  PlateStatusDraft expectedOriginalStatus = PlateStatusDraft(
    customStatus: '',
  );
  String? expectedStatusSourcePath;

  PlateStatusDraft get statusDraft => PlateStatusDraft(
        customStatus: customStatusController.text,
      );

  bool get statusLookupInProgress =>
      statusLookupState == PlateStatusLookupState.loading;

  bool get statusLookupReadyForSubmit =>
      statusLookupState == PlateStatusLookupState.found ||
      statusLookupState == PlateStatusLookupState.notFound ||
      statusLookupState == PlateStatusLookupState.failed;

  bool get statusSnapshotValidationRequired =>
      statusEditedByUser ||
      statusWriteRequested ||
      statusLookupState == PlateStatusLookupState.found ||
      statusLookupState == PlateStatusLookupState.notFound;

  void beginStatusLookup() {
    fetchedCustomStatus = null;
    customStatusController.clear();
    statusLookupState = PlateStatusLookupState.loading;
    expectedOriginalStatus = PlateStatusDraft(customStatus: '');
    expectedStatusSourcePath = null;
    statusEditedByUser = false;
    statusWriteRequested = false;
    statusDeletionRequested = false;
  }

  void resetStatusLookupToIdle() {
    fetchedCustomStatus = null;
    customStatusController.clear();
    statusLookupState = PlateStatusLookupState.idle;
    expectedOriginalStatus = PlateStatusDraft(customStatus: '');
    expectedStatusSourcePath = null;
    statusEditedByUser = false;
    statusWriteRequested = false;
    statusDeletionRequested = false;
  }

  void applyStatusInactive() {
    fetchedCustomStatus = null;
    customStatusController.clear();
    statusLookupState = PlateStatusLookupState.inactive;
    expectedOriginalStatus = PlateStatusDraft(customStatus: '');
    expectedStatusSourcePath = null;
    statusEditedByUser = false;
    statusWriteRequested = false;
    statusDeletionRequested = false;
  }

  void applyFetchedStatus({
    required String? customStatus,
    required String sourcePath,
  }) {
    final draft = PlateStatusDraft(customStatus: customStatus ?? '');
    fetchedCustomStatus = draft.customStatus.isEmpty ? null : draft.customStatus;
    customStatusController.text = draft.customStatus;
    statusLookupState = PlateStatusLookupState.found;
    expectedOriginalStatus = draft;
    expectedStatusSourcePath = sourcePath.trim().isEmpty ? null : sourcePath.trim();
    statusEditedByUser = false;
    statusWriteRequested = true;
    statusDeletionRequested = draft.isEmpty;
  }

  void applyStatusNotFound() {
    fetchedCustomStatus = null;
    customStatusController.clear();
    statusLookupState = PlateStatusLookupState.notFound;
    expectedOriginalStatus = PlateStatusDraft(customStatus: '');
    expectedStatusSourcePath = null;
    statusEditedByUser = false;
    statusWriteRequested = true;
    statusDeletionRequested = true;
  }

  void applyStatusLookupFailed() {
    fetchedCustomStatus = null;
    customStatusController.clear();
    statusLookupState = PlateStatusLookupState.failed;
    expectedOriginalStatus = PlateStatusDraft(customStatus: '');
    expectedStatusSourcePath = null;
    statusEditedByUser = false;
    statusWriteRequested = false;
    statusDeletionRequested = false;
  }

  void markStatusDraftEdited() {
    statusEditedByUser = true;
    statusWriteRequested = true;
    statusDeletionRequested = statusDraft.isEmpty;
  }

  void markStatusDraftPersisted() {
    final draft = statusDraft;
    fetchedCustomStatus = draft.customStatus.isEmpty ? null : draft.customStatus;
    statusWriteRequested = false;
    statusDeletionRequested = false;
    statusEditedByUser = false;
    statusLookupState = PlateStatusLookupState.found;
    expectedOriginalStatus = draft;
  }

  void clearStatusDraft() {
    fetchedCustomStatus = null;
    customStatusController.clear();
    statusWriteRequested = false;
    statusDeletionRequested = false;
    statusEditedByUser = false;
    statusLookupState = PlateStatusLookupState.notFound;
    expectedOriginalStatus = PlateStatusDraft(customStatus: '');
    expectedStatusSourcePath = null;
  }

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

  void clearParkingSelection() {
    clearLocation();
    priority1SlotKey = null;
    priority2SlotKey = null;
    priority3SlotKey = null;
  }

  void clearVehicleInfo() {
    selectedManufacturerName = null;
    selectedModelName = null;
    selectedSectorId = null;
    selectedSectorName = null;
    priority1SlotKey = null;
    priority2SlotKey = null;
    priority3SlotKey = null;
  }

  void resetForm() {
    clearInput();
    clearLocation();
    capturedImages.clear();
    selectedBill = null;
    selectedBasicStandard = 0;
    selectedBasicAmount = 0;
    selectedAddStandard = 0;
    selectedAddAmount = 0;

    customStatusController.clear();
    countTypeController.clear();

    fetchedCustomStatus = null;
    statusWriteRequested = false;
    statusDeletionRequested = false;
    statusEditedByUser = false;
    statusLookupState = PlateStatusLookupState.idle;
    expectedOriginalStatus = PlateStatusDraft(customStatus: '');
    expectedStatusSourcePath = null;
    isThreeDigit = true;
    selectedBillType = '변동';
    clearVehicleInfo();
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

  void setSelectedSector(SectorModel sector) {
    selectedSectorId = sector.id.trim();
    selectedSectorName = sector.name.trim();
  }

  void clearSelectedSector() {
    selectedSectorId = null;
    selectedSectorName = null;
  }

  void clearBillingSelection({bool resetType = true}) {
    if (resetType) selectedBillType = '변동';
    selectedBill = null;
    countTypeController.clear();
    selectedBasicStandard = 0;
    selectedBasicAmount = 0;
    selectedAddStandard = 0;
    selectedAddAmount = 0;
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
    final isMonthly = selectedBillType == '정기';
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '입차 상태 메모 삭제',
      initialMessage: '저장된 상태 메모를 삭제하고 있습니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 상태 메모 삭제 로그를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 상태 메모 삭제 로그를 콘솔에 기록합니다.',
    );
    trace.log(
      'plate=$plateNumber area=$area scope=${isMonthly ? 'monthly' : 'history'} '
      'memoLength=${customStatusController.text.trim().length} ',
      progress: .28,
    );

    try {
      if (isMonthly) {
        await plateRepo.clearMonthlyMemoAndStatus(
          plateNumber: plateNumber,
          area: area,
        );
      } else {
        await plateRepo.deletePlateStatus(plateNumber, area);
      }
      clearStatusDraft();
      await trace.succeed('저장된 상태 메모를 삭제했습니다.');
    } catch (error, stackTrace) {
      await trace.fail(
        '상태 메모 삭제에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<bool> _reportSectorWorkflow({
    required BuildContext context,
    required String initialMessage,
    required List<String> lines,
    required bool success,
    required String resultMessage,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (!context.mounted) return false;
    final operationTrace = await DeveloperOperationTrace.start(
      context: context,
      title: '입차 방문처 선택',
      initialMessage: initialMessage,
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 방문처 선택 로그를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 방문처 선택 로그를 콘솔에 기록합니다.',
    );
    for (final line in lines) {
      operationTrace.log(line);
    }
    if (success) {
      await operationTrace.succeed(resultMessage);
    } else {
      await operationTrace.fail(
        resultMessage,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return operationTrace.developerMode;
  }

  Future<_SectorEntryResolution> _resolveSectorForEntry({
    required BuildContext context,
    required AreaState areaState,
    required String area,
    ActionTraceController? trace,
  }) async {
    final canUseSector = areaState.capabilitiesOfCurrentArea.contains(
      Capability.sector,
    );
    trace?.add('canUseSector=$canUseSector');
    debugPrint(
      '[InputPlateController][Sector] capability check '
      'area=$area canUseSector=$canUseSector',
    );

    if (!canUseSector) {
      clearSelectedSector();
      return const _SectorEntryResolution(proceed: true);
    }

    final selectedId = selectedSectorId?.trim() ?? '';
    final selectedName = selectedSectorName?.trim() ?? '';
    if (selectedId.isEmpty || selectedName.isEmpty) {
      trace?.add('중단: Sector 미선택');
      if (context.mounted) {
        showFailedSnackbar(
          context,
          '방문 구역을 선택해주세요.',
          useCommonUi: true,
        );
      }
      return const _SectorEntryResolution(proceed: false);
    }

    final sectorState = context.read<SectorState>();
    final cacheKey = SectorState.cacheKeyForArea(area);
    final wait = Stopwatch()..start();
    await sectorState.waitUntilReady();
    wait.stop();
    if (!context.mounted) {
      return const _SectorEntryResolution(proceed: false);
    }

    final currentArea = areaState.currentArea.trim();
    SectorModel? resolved;
    for (final sector in sectorState.sectors) {
      if (sector.id.trim() == selectedId) {
        resolved = sector;
        break;
      }
    }
    final confirmed = resolved;
    final valid = currentArea == area.trim() &&
        confirmed != null &&
        confirmed.area.trim() == currentArea &&
        confirmed.id.trim() == selectedId &&
        confirmed.name.trim() == selectedName;

    debugPrint(
      '[InputPlateController][Sector] selected validation '
      'area=$area currentArea=$currentArea cacheKey=$cacheKey '
      'selectedId=$selectedId selectedName=$selectedName '
      'resolved=${confirmed != null} waitMs=${wait.elapsedMilliseconds}',
    );

    if (!valid) {
      clearSelectedSector();
      trace?.add('중단: Sector 최신 로컬 목록 재검증 실패');
      final developerMode = await _reportSectorWorkflow(
        context: context,
        initialMessage: '선택한 방문 구역을 다시 확인하고 있습니다.',
        lines: <String>[
          'requestedArea=$area',
          'currentArea=$currentArea',
          'cacheKey=$cacheKey',
          'selectedId=$selectedId',
          'selectedName=$selectedName',
          'resolved=${confirmed != null}',
          'cacheWaitMs=${wait.elapsedMilliseconds}',
          'firebaseRead=false',
        ],
        success: false,
        resultMessage: '선택한 방문 구역이 현재 로컬 운영 데이터와 일치하지 않습니다.',
        error: StateError('방문 구역 선택 정보가 최신 로컬 데이터와 일치하지 않습니다.'),
      );
      if (!developerMode && context.mounted) {
        await StatusDialog.showFailure(
          context,
          title: '방문 구역을 다시 선택해주세요.',
          description: '현재 지역 또는 로컬 방문 구역 정보가 변경되었습니다.',
          useCommonUi: true,
        );
      }
      return const _SectorEntryResolution(proceed: false);
    }

    trace?.add('sectorId=${confirmed.id} sectorName=${confirmed.name}');
    return _SectorEntryResolution(proceed: true, sector: confirmed);
  }

  Future<bool> submitPlateEntry(
    BuildContext context,
    VoidCallback refreshUI, {
    ActionTraceController? trace,
  }) async {
    trace?.add('입차 처리 시작');

    if (!statusLookupReadyForSubmit) {
      final stateName = statusLookupState.name;
      final message = statusLookupInProgress
          ? '상태 정보를 확인하고 있습니다. 확인이 끝난 뒤 다시 시도해 주세요.'
          : statusLookupState == PlateStatusLookupState.inactive
              ? '상태 정보의 유효기간을 다시 확인해 주세요.'
              : '상태 정보 확인이 아직 시작되지 않았습니다. 번호판을 다시 확인해 주세요.';
      debugPrint(
        '[InputPlateController][StatusLookup] submitBlocked=true '
        'state=$stateName plate=${buildPlateNumber()}',
      );
      trace?.add('중단: 상태 조회 미완료 state=$stateName');
      if (context.mounted && trace == null) {
        final lookupTrace = await DeveloperOperationTrace.start(
          context: context,
          title: '입차 상태 조회 확인',
          initialMessage: '입차 전 상태 정보 확인 여부를 검사하고 있습니다.',
          useCommonUi: true,
          developerModeMessage:
              '개발자 모드 ON: 상태 조회 차단 로그를 복사할 수 있습니다.',
          standardModeMessage:
              '개발자 모드 OFF: 상태 조회 차단 로그를 콘솔에 기록합니다.',
        );
        lookupTrace.log(
          'plate=${buildPlateNumber()} lookupState=$stateName '
          'submitBlocked=true preserveExistingStatus=true',
          progress: .62,
        );
        await lookupTrace.fail(message);
      }
      if (context.mounted) {
        showFailedSnackbar(context, message, useCommonUi: true);
      }
      return false;
    }

    final isValid = isInputValid();
    trace?.add('isInputValid=$isValid');
    if (!isValid) {
      trace?.add('중단: 번호판 입력 불완전');
      if (context.mounted) {
        showFailedSnackbar(context, '번호판 입력을 확인해주세요.', useCommonUi: true);
      }
      return false;
    }

    final plateNumber = buildPlateNumber();
    final areaState = context.read<AreaState>();
    final area = areaState.currentArea;
    final division = areaState.currentDivision;
    final userName = context.read<UserState>().name;
    final billState = context.read<BillState>();
    final canUseBill = areaState.capabilitiesOfCurrentArea.contains(
      Capability.bill,
    );
    final hasAnyBill = canUseBill &&
        (billState.generalBills.isNotEmpty || billState.regularBills.isNotEmpty);

    trace?.add('plateNumber=$plateNumber');
    trace?.add('area=$area division=$division');
    trace?.add('canUseBill=$canUseBill hasAnyBill=$hasAnyBill');

    final location = locationController.text.trim();
    isLocationSelected = location.isNotEmpty;
    trace?.add('location="$location" isLocationSelected=$isLocationSelected');

    if (!isMinorMode && !isLocationSelected) {
      trace?.add('중단: 주차 위치 미선택');
      if (context.mounted) {
        showFailedSnackbar(context, '주차 위치를 선택해주세요.', useCommonUi: true);
      }
      return false;
    }

    if (canUseBill &&
        selectedBillType == '정기' &&
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
        showFailedSnackbar(context, '정산 유형을 선택해주세요.', useCommonUi: true);
      }
      return false;
    }

    final sectorResolution = await _resolveSectorForEntry(
      context: context,
      areaState: areaState,
      area: area,
      trace: trace,
    );
    if (!sectorResolution.proceed || !context.mounted) {
      trace?.add('중단: Sector 준비 실패 또는 취소');
      return false;
    }
    final selectedSector = sectorResolution.sector;
    DeveloperOperationTrace? statusOperationTrace;
    if (trace == null && context.mounted) {
      statusOperationTrace = await DeveloperOperationTrace.start(
        context: context,
        title: '입차 상태 정보 저장',
        initialMessage: '입차 정보와 상태 메모를 저장하고 있습니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 상태 저장 로그를 복사할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: 상태 저장 로그를 콘솔에 기록합니다.',
      );
      final draft = statusDraft;
      statusOperationTrace.log(
        'plate=$plateNumber area=$area '
        'memoLength=${draft.customStatus.length} '

        'writeRequested=$statusWriteRequested '
        'deleteRequested=$statusDeletionRequested '
        'lookupState=${statusLookupState.name} '
        'edited=$statusEditedByUser '
        'sourcePath=${expectedStatusSourcePath ?? ''} '
        'snapshotValidation=$statusSnapshotValidationRequired '
        'scope=${selectedBillType == '정기' ? 'monthly' : 'history'} '
        'saveOwner=PlateCreationService',
        progress: .24,
      );
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
          useCommonUi: true,
        );
      }

      final draft = statusDraft;
      debugPrint(
        '[InputPlateController][Status] plate=$plateNumber area=$area '
        'memoLength=${draft.customStatus.length} '
        'writeRequested=$statusWriteRequested '
        'deleteRequested=$statusDeletionRequested '
        'lookupState=${statusLookupState.name} '
        'edited=$statusEditedByUser '
        'sourcePath=${expectedStatusSourcePath ?? ''} '
        'snapshotValidation=$statusSnapshotValidationRequired '
        'saveOwner=PlateCreationService',
      );
      trace?.add(
        '상태 초안 memoLength=${draft.customStatus.length} '

        'lookupState=${statusLookupState.name} '
        'edited=$statusEditedByUser saveOwner=PlateCreationService',
      );
      trace?.add('입차 등록 시작');
      final wasSuccessful = await InputPlateService.registerPlateEntry(
        context: context,
        plateNumber: plateNumber,
        location: isLocationSelected ? location : '',
        isLocationSelected: isLocationSelected,
        imageUrls: uploadResult.uploadedUrls,
        selectedBill: canUseBill ? selectedBill : null,
        statusWriteRequested: statusWriteRequested,
        statusLookupState: statusLookupState,
        statusEditedByUser: statusEditedByUser,
        expectedOriginalStatus: expectedOriginalStatus,
        expectedStatusSourcePath: expectedStatusSourcePath,
        basicStandard: canUseBill ? selectedBasicStandard : 0,
        basicAmount: canUseBill ? selectedBasicAmount : 0,
        addStandard: canUseBill ? selectedAddStandard : 0,
        addAmount: canUseBill ? selectedAddAmount : 0,
        region: dropdownValue,
        customStatus: draft.customStatus,
        selectedBillType: canUseBill ? selectedBillType : '변동',
        manufacturerName: selectedManufacturerName,
        modelName: selectedModelName,
        priority1SlotKey: priority1SlotKey,
        priority2SlotKey: priority2SlotKey,
        priority3SlotKey: priority3SlotKey,
        sectorId: selectedSector?.id,
        sectorName: selectedSector?.name,
      );
      trace?.add('입차 등록 결과=$wasSuccessful');

      if (!context.mounted) {
        trace?.add('중단: context unmounted after register');
        if (statusOperationTrace != null) {
          await statusOperationTrace.fail('화면 종료로 상태 저장 결과를 완료하지 못했습니다.');
        }
        return false;
      }

      if (!wasSuccessful) {
        trace?.add('중단: registerPlateEntry returned false');
        if (statusOperationTrace != null) {
          await statusOperationTrace.fail('입차 상태 정보 저장이 완료되지 않았습니다.');
        }
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

      trace?.add('상태/메모 저장은 PlateCreationService 동일 transaction에서 완료');

      trace?.add('입차 처리 성공');
      if (statusOperationTrace != null) {
        await statusOperationTrace.succeed(
          '입차 정보와 상태 메모 저장이 완료되었습니다.',
        );
      }
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
      if (statusOperationTrace != null) {
        await statusOperationTrace.fail(
          '입차 상태 정보 저장에 실패했습니다.',
          error: e,
          stackTrace: st,
        );
      }
      if (context.mounted) {
        showFailedSnackbar(context, '입차 처리 실패: $e', useCommonUi: true);
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
