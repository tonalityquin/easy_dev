import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../../../app/models/capability.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/payment/applications/bill_state.dart';
import '../../../../features/payment/domain/models/bill_model.dart';
import '../../../../features/payment/domain/models/regular_bill_model.dart';
import '../../../plate/application/double/double_plate_state.dart';
import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/models/plate_model.dart';
import '../../../plate/domain/models/plate_status_draft.dart';
import '../../../plate/domain/models/plate_status_lookup_result.dart';
import '../../../plate/domain/models/plate_status_scope.dart';
import '../../../plate/domain/repositories/plate_repository.dart';
import '../../../plate/domain/services/plate_status_record.dart';
import '../../../plate/widgets/action_trace_dialog.dart';
import '../application/modify_plate_service.dart';

class ModifyPlateController {
  final BuildContext context;
  final PlateModel plate;
  final PlateType collectionKey;

  final TextEditingController controllerFrontdigit;
  final TextEditingController controllerMidDigit;
  final TextEditingController controllerBackDigit;
  final TextEditingController locationController;
  final TextEditingController customStatusController = TextEditingController();

  final List<XFile> capturedImages;
  final List<String> existingImageUrls;


  CameraController? cameraController;
  bool isCameraInitialized = false;
  bool _isDisposing = false;

  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;
  int selectedRegularAmount = 0;
  int selectedRegularDurationHours = 0;

  String? selectedBill;
  String selectedBillType = '변동';
  String dropdownValue = '전국';
  String? selectedBillCountType;
  dynamic selectedBillModel;

  String? selectedManufacturerName;
  String? selectedModelName;
  String? priority1SlotKey;
  String? priority2SlotKey;
  String? priority3SlotKey;
  String? selectedSectorId;
  String? selectedSectorName;

  bool isLocationSelected = false;

  late PlateStatusDraft originalStatusDraft;
  late PlateStatusDraft expectedPersistedStatusDraft;
  bool statusMarkedForDeletion = false;
  bool statusContextResolved = false;
  PlateStatusScope? statusScope;
  String? expectedStatusSourcePath;

  PlateStatusDraft get statusDraft => PlateStatusDraft(
        customStatus: customStatusController.text,
      );

  bool get hasStatusChanges => !originalStatusDraft.sameAs(statusDraft);

  bool get hasOriginalStatus => !originalStatusDraft.isEmpty;

  void handleStatusTextChanged() {
    statusMarkedForDeletion = statusDraft.isEmpty && hasOriginalStatus;
  }

  void clearStatusDraft() {
    customStatusController.clear();
    statusMarkedForDeletion = hasOriginalStatus;
    debugPrint(
      '[ModifyPlateController][Status] localClear=true '
      'plate=${plate.plateNumber} deletePending=$statusMarkedForDeletion',
    );
  }

  final List<String> _regions = [
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
    '협정'
  ];

  List<String> get regions => _regions;

  List<String> get selectedParkingPriorities {
    return <String>[
      if (priority1SlotKey != null && priority1SlotKey!.trim().isNotEmpty)
        priority1SlotKey!.trim(),
      if (priority2SlotKey != null && priority2SlotKey!.trim().isNotEmpty)
        priority2SlotKey!.trim(),
      if (priority3SlotKey != null && priority3SlotKey!.trim().isNotEmpty)
        priority3SlotKey!.trim(),
    ];
  }

  ModifyPlateController({
    required this.context,
    required this.plate,
    required this.collectionKey,
    required this.controllerFrontdigit,
    required this.controllerMidDigit,
    required this.controllerBackDigit,
    required this.locationController,
    required this.capturedImages,
    required this.existingImageUrls,
  });

  void initializePlate() {
    if (plate.imageUrls != null) {
      existingImageUrls.addAll(plate.imageUrls!);
    }
  }

  Future<void> disposeCamera() async {
    if (_isDisposing) return;
    _isDisposing = true;

    try {
      if (cameraController?.value.isInitialized ?? false) {
        await cameraController?.dispose();
      }
      cameraController = null;
      isCameraInitialized = false;
    } catch (e) {
      debugPrint('❌ 카메라 dispose 중 오류: $e');
    }
    _isDisposing = false;
  }

  void initializeFieldValues() {
    final plateNum = plate.plateNumber.replaceAll('-', '');
    final regExp = RegExp(r'^(\d{2,3})([가-힣]?)(\d{4})$');
    final match = regExp.firstMatch(plateNum);

    if (match != null) {
      controllerFrontdigit.text = match.group(1) ?? '';
      controllerMidDigit.text = match.group(2) ?? '';
      controllerBackDigit.text = match.group(3) ?? '';
    } else {
      controllerFrontdigit.text =
          plateNum.length >= 7 ? plateNum.substring(0, 3) : '';
      controllerMidDigit.text = '-';
      controllerBackDigit.text =
          plateNum.length >= 7 ? plateNum.substring(3) : '';
    }

    dropdownValue = plate.region ?? '전국';
    locationController.text = plate.location;

    selectedBill = plate.billingType;
    selectedBillType = _determineBillType(plate.billingType);
    selectedBillCountType = plate.billingType;

    selectedManufacturerName = plate.manufacturerName;
    selectedModelName = plate.modelName;
    priority1SlotKey = plate.parkingPriority1SlotKey;
    priority2SlotKey = plate.parkingPriority2SlotKey;
    priority3SlotKey = plate.parkingPriority3SlotKey;
    selectedSectorId = plate.sectorId;
    selectedSectorName = plate.sectorName;

    selectedBasicStandard = plate.basicStandard ?? 0;
    selectedBasicAmount = plate.basicAmount ?? 0;
    selectedAddStandard = plate.addStandard ?? 0;
    selectedAddAmount = plate.addAmount ?? 0;
    selectedRegularAmount = plate.regularAmount ?? 0;
    selectedRegularDurationHours = plate.regularDurationValue ?? 0;

    isLocationSelected = locationController.text.isNotEmpty;
    originalStatusDraft = PlateStatusDraft(
      customStatus: plate.customStatus ?? '',
    );
    expectedPersistedStatusDraft = originalStatusDraft;
    customStatusController.text = originalStatusDraft.customStatus;
    statusMarkedForDeletion = false;
  }

  String _determineBillType(String? billingType) {
    if (billingType == null || billingType.isEmpty) return '변동';
    if (billingType.contains('고정')) return '고정';
    if ((plate.regularAmount ?? 0) > 0) return '고정';
    return '변동';
  }

  Future<void> resolveStatusContext() async {
    final repo = context.read<PlateRepository>();
    final scope = await repo.resolvePlateStatusScope(
      plateNumber: plate.plateNumber,
      area: plate.area,
      billingType: plate.billingType,
      regularAmount: plate.regularAmount ?? 0,
    );
    final lookup = await repo.lookupPlateStatus(
      plateNumber: plate.plateNumber,
      area: plate.area,
      scope: scope,
    );
    if (lookup.isFailed) {
      throw PlateStatusReadException(
        '상태 메모 최신 정보를 확인하지 못했습니다.',
        cause: lookup.error,
      );
    }
    if (lookup.isInactive) {
      throw const PlateStatusScopeException(
        '월정기 이용 기간이 만료되어 일반 상태 범위를 다시 확인해야 합니다.',
      );
    }

    final draftBeforeResolution = statusDraft;
    final editedBeforeResolution =
        !originalStatusDraft.sameAs(draftBeforeResolution);
    final authoritativeDraft = lookup.isFound
        ? PlateStatusDraft(
            customStatus: lookup.record?.customStatus ?? '',
          )
        : PlateStatusDraft(
            customStatus: plate.customStatus ?? '',
          );

    statusScope = scope;
    expectedStatusSourcePath = lookup.sourcePath;
    expectedPersistedStatusDraft = lookup.isFound
        ? authoritativeDraft
        : PlateStatusDraft(customStatus: '');
    originalStatusDraft = authoritativeDraft;
    if (!editedBeforeResolution) {
      customStatusController.text = authoritativeDraft.customStatus;
    }
    statusMarkedForDeletion =
        statusDraft.isEmpty && !originalStatusDraft.isEmpty;
    statusContextResolved = true;

    debugPrint(
      '[ModifyPlateController][StatusContext] plate=${plate.plateNumber} '
      'scope=${scope.storageLabel} lookup=${lookup.state.name} '
      'sourcePath=${lookup.sourcePath ?? ''} '
      'memoLength=${authoritativeDraft.customStatus.length}',
    );
  }

  void onBillTypeChanged(String type) {
    if (type != selectedBillType) {
      debugPrint('❌ 정산 유형 변경은 허용되지 않습니다. 기존: $selectedBillType → 시도: $type');
      return;
    }
  }

  void applyBillDefaults(dynamic bill) {
    if (bill == null) return;

    selectedBillModel = bill;
    selectedBillCountType = bill.countType;
    selectedBill = bill.countType;

    if (bill is BillModel) {
      selectedBillType = '변동';

      selectedBasicAmount = bill.basicAmount ?? 0;
      selectedBasicStandard = bill.basicStandard ?? 0;
      selectedAddAmount = bill.addAmount ?? 0;
      selectedAddStandard = bill.addStandard ?? 0;

      selectedRegularAmount = 0;
      selectedRegularDurationHours = 0;
    } else if (bill is RegularBillModel) {
      selectedBillType = '고정';

      selectedRegularAmount = bill.regularAmount;
      selectedRegularDurationHours = bill.regularDurationValue;

      selectedBasicAmount = 0;
      selectedBasicStandard = 0;
      selectedAddAmount = 0;
      selectedAddStandard = 0;
    }
  }

  Future<bool> handleAction({
    ActionTraceController? trace,
  }) async {
    trace?.add('수정 처리 시작');

    final billState = context.read<BillState>();
    final allBills = [...billState.generalBills, ...billState.regularBills];
    trace?.add('allBills=${allBills.length}');

    final normalizedSelectedBill = selectedBill?.trim();
    selectedBill =
        (normalizedSelectedBill == null || normalizedSelectedBill.isEmpty)
            ? null
            : normalizedSelectedBill;

    trace?.add(
      'selectedBillType=$selectedBillType selectedBill=${selectedBill ?? ''}',
    );

    if (allBills.isNotEmpty &&
        (selectedBill == null || selectedBill!.isEmpty)) {
      trace?.add('중단: selectedBill 누락');
      if (context.mounted) {
        showFailedSnackbar(
          context,
          '정산 유형 정보가 비어 있습니다.',
          useCommonUi: true,
        );
      }
      return false;
    }

    final areaState = context.read<AreaState>();
    final canUseSector = areaState.capabilitiesOfCurrentArea.contains(
      Capability.sector,
    );
    final effectiveSectorId = canUseSector ? selectedSectorId : plate.sectorId;
    final effectiveSectorName =
        canUseSector ? selectedSectorName : plate.sectorName;
    if (!statusContextResolved) {
      try {
        await resolveStatusContext();
      } catch (error) {
        trace?.add('중단: 상태 저장 범위 확인 실패 error=$error');
        if (context.mounted) {
          showFailedSnackbar(
            context,
            '상태 메모 최신 정보를 확인하지 못해 저장하지 않았습니다.',
            useCommonUi: true,
          );
        }
        return false;
      }
    }

    final resolvedScope = statusScope;
    if (resolvedScope == null) {
      trace?.add('중단: 상태 저장 범위 없음');
      return false;
    }

    final draft = statusDraft;
    final statusChanged = hasStatusChanges;
    final userState = context.read<UserState>();

    trace?.add(
      'status memoLength=${draft.customStatus.length} '
      'changed=$statusChanged deletePending=$statusMarkedForDeletion '
      'scope=${resolvedScope.storageLabel}',
    );
    debugPrint(
      '[ModifyPlateController][Status] plate=${plate.plateNumber} '
      'memoLength=${draft.customStatus.length} '
      'changed=$statusChanged deletePending=$statusMarkedForDeletion '
      'scope=${resolvedScope.storageLabel}',
    );

    final service = ModifyPlateService(
      context: context,
      capturedImages: capturedImages,
      existingImageUrls: existingImageUrls,
      collectionKey: collectionKey,
      originalPlate: plate,
      controllerFrontdigit: controllerFrontdigit,
      controllerMidDigit: controllerMidDigit,
      controllerBackDigit: controllerBackDigit,
      locationController: locationController,
      selectedBasicStandard: selectedBasicStandard,
      selectedBasicAmount: selectedBasicAmount,
      selectedAddStandard: selectedAddStandard,
      selectedAddAmount: selectedAddAmount,
      selectedBill: selectedBill,
      dropdownValue: dropdownValue,
      selectedRegularAmount: selectedRegularAmount,
      selectedRegularDurationHours: selectedRegularDurationHours,
      manufacturerName: selectedManufacturerName,
      modelName: selectedModelName,
      priority1SlotKey: priority1SlotKey,
      priority2SlotKey: priority2SlotKey,
      priority3SlotKey: priority3SlotKey,
      selectedSectorId: effectiveSectorId,
      selectedSectorName: effectiveSectorName,
      statusScope: resolvedScope,
      statusChanged: statusChanged,
      expectedOriginalStatus: expectedPersistedStatusDraft,
      expectedStatusSourcePath: expectedStatusSourcePath,
      statusActorId: userState.session?.id ?? '',
      statusActorName: userState.name.trim(),
    );

    final plateNumber = service.composePlateNumber();
    final newLocation = locationController.text.trim();
    final newBillingType = selectedBill;
    final updatedCustomStatus = draft.customStatus;

    trace?.add('plateNumber=$plateNumber');
    trace?.add('newLocation="$newLocation"');
    trace?.add(
      'capability.sector=$canUseSector '
      'sectorId=${effectiveSectorId ?? ''} '
      'sectorName=${effectiveSectorName ?? ''}',
    );
    debugPrint(
      '[ModifyPlateController][Sector] plate=$plateNumber area=${plate.area} '
      'capability.sector=$canUseSector '
      'sectorId=${effectiveSectorId ?? ''} '
      'sectorName=${effectiveSectorName ?? ''}',
    );

    try {
      trace?.add('사진 병합 업로드 시작');
      final mergedImageUrls = await service.uploadAndMergeImages(plateNumber);
      trace?.add('사진 병합 업로드 완료 count=${mergedImageUrls.length}');

      trace?.add('차량 정보 업데이트 시작');
      final success = await service.updatePlateInfo(
        plateNumber: plateNumber,
        imageUrls: mergedImageUrls,
        newLocation: newLocation,
        newBillingType: newBillingType,
        updatedCustomStatus: updatedCustomStatus,
      );
      trace?.add('차량 정보 업데이트 결과=$success');

      if (!success) {
        trace?.add('중단: updatePlateInfo returned false');
        return false;
      }

      trace?.add('차량 문서와 상태 문서 transaction 저장 완료');

      final updatedPlate = PlateModel(
        id: plate.id,
        addAmount: selectedAddAmount,
        addStandard: selectedAddStandard,
        area: plate.area,
        basicAmount: selectedBasicAmount,
        basicStandard: selectedBasicStandard,
        billingType: newBillingType,
        customStatus: updatedCustomStatus,
        endTime: plate.endTime,
        imageUrls: mergedImageUrls,
        isLockedFee: plate.isLockedFee,
        isSelected: false,
        location: newLocation,
        lockedAtTimeInSeconds: plate.lockedAtTimeInSeconds,
        lockedFeeAmount: plate.lockedFeeAmount,
        logs: plate.logs,
        paymentMethod: plate.paymentMethod,
        manufacturerName: selectedManufacturerName,
        modelName: selectedModelName,
        parkingPriority1SlotKey: priority1SlotKey,
        parkingPriority2SlotKey: priority2SlotKey,
        parkingPriority3SlotKey: priority3SlotKey,
        plateFourDigit: plate.plateFourDigit,
        plateNumber: plateNumber,
        region: dropdownValue,
        regularAmount: selectedRegularAmount,
        regularDurationValue: selectedRegularDurationHours,
        requestTime: plate.requestTime,
        selectedBy: null,
        type: plate.type,
        updatedAt: plate.updatedAt,
        userAdjustment: plate.userAdjustment,
        userName: plate.userName,
        feeMode: plate.feeMode,
        sectorId: effectiveSectorId,
        sectorName: effectiveSectorName,
      );

      final plateState = context.read<DoublePlateState>();
      trace?.add('로컬 상태 반영 시작');
      await plateState.doubleUpdatePlateLocally(collectionKey, updatedPlate);
      trace?.add('로컬 상태 반영 완료');
      trace?.add('수정 처리 성공');
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
        showFailedSnackbar(
          context,
          '수정 처리 실패: $e',
          useCommonUi: true,
        );
      }
      return false;
    }
  }

  void dispose() {
    controllerFrontdigit.dispose();
    controllerMidDigit.dispose();
    controllerBackDigit.dispose();
    locationController.dispose();
    customStatusController.dispose();
    disposeCamera();
  }
}
