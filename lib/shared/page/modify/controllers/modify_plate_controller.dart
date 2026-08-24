import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
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
import '../application/modify_plate_service.dart';

class ModifyPlateController {
  final BuildContext context;
  final PlateModel plate;
  final PlateType collectionKey;
  final String capabilityArea;
  final bool canUseBill;
  final bool canUseSector;

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

  String get currentPlateNumberCompact =>
      '${controllerFrontdigit.text}${controllerMidDigit.text}${controllerBackDigit.text}'
          .replaceAll('-', '')
          .replaceAll(' ', '')
          .trim();

  String get currentPlateNumberDisplay {
    final front = controllerFrontdigit.text.trim();
    final middle = controllerMidDigit.text.trim();
    final back = controllerBackDigit.text.trim();
    return <String>[front, middle, back]
        .where((value) => value.isNotEmpty)
        .join('-');
  }

  String get originalPlateNumberCompact =>
      plate.plateNumber.replaceAll('-', '').replaceAll(' ', '').trim();

  String get originalRegion {
    final value = plate.region?.trim() ?? '';
    return value.isEmpty ? '전국' : value;
  }

  bool get hasPlateNumberChanges =>
      currentPlateNumberCompact != originalPlateNumberCompact;

  bool get hasRegionChanges => dropdownValue.trim() != originalRegion;

  bool get hasVehicleIdentityChanges =>
      hasPlateNumberChanges || hasRegionChanges;

  bool get hasLocationChanges {
    final currentLocation = locationController.text.trim();
    final originalLocation = plate.location.trim();
    final currentPriority1 = priority1SlotKey?.trim() ?? '';
    final currentPriority2 = priority2SlotKey?.trim() ?? '';
    final currentPriority3 = priority3SlotKey?.trim() ?? '';
    final originalPriority1 = plate.parkingPriority1SlotKey?.trim() ?? '';
    final originalPriority2 = plate.parkingPriority2SlotKey?.trim() ?? '';
    final originalPriority3 = plate.parkingPriority3SlotKey?.trim() ?? '';
    return currentLocation != originalLocation ||
        currentPriority1 != originalPriority1 ||
        currentPriority2 != originalPriority2 ||
        currentPriority3 != originalPriority3;
  }

  bool get hasBillingSelection {
    if (!canUseBill) return false;
    return (selectedBill?.trim().isNotEmpty ?? false) ||
        (selectedBillCountType?.trim().isNotEmpty ?? false);
  }

  bool get hasBillingChanges {
    if (!canUseBill) return false;
    final currentBill = selectedBill?.trim() ?? '';
    final originalBill = plate.billingType?.trim() ?? '';
    return currentBill != originalBill ||
        selectedBillType.trim() != _determineBillType() ||
        selectedBasicStandard != (plate.basicStandard ?? 0) ||
        selectedBasicAmount != (plate.basicAmount ?? 0) ||
        selectedAddStandard != (plate.addStandard ?? 0) ||
        selectedAddAmount != (plate.addAmount ?? 0) ||
        selectedRegularAmount != (plate.regularAmount ?? 0) ||
        selectedRegularDurationHours != (plate.regularDurationValue ?? 0);
  }

  bool get hasSectorChanges {
    if (!canUseSector) return false;
    final currentSectorId = selectedSectorId?.trim() ?? '';
    final originalSectorId = plate.sectorId?.trim() ?? '';
    final currentSectorName = selectedSectorName?.trim() ?? '';
    final originalSectorName = plate.sectorName?.trim() ?? '';
    return currentSectorId != originalSectorId ||
        currentSectorName != originalSectorName;
  }

  bool get hasPhotoChanges => capturedImages.isNotEmpty;

  bool get hasStatusChanges => !originalStatusDraft.sameAs(statusDraft);

  bool get hasOriginalStatus => !originalStatusDraft.isEmpty;

  int get changeCount {
    var count = 0;
    if (hasVehicleIdentityChanges) count += 1;
    if (hasLocationChanges) count += 1;
    if (hasPhotoChanges) count += 1;
    if (hasSectorChanges) count += 1;
    if (hasBillingChanges) count += 1;
    if (hasStatusChanges) count += 1;
    return count;
  }

  bool get hasUnsavedChanges => changeCount > 0;

  void handleStatusTextChanged() {
    statusMarkedForDeletion = statusDraft.isEmpty && hasOriginalStatus;
  }

  void invalidateStatusContext() {
    statusContextResolved = false;
    statusScope = null;
    expectedStatusSourcePath = null;
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

  void clearParkingSelection() {
    locationController.clear();
    isLocationSelected = false;
    priority1SlotKey = null;
    priority2SlotKey = null;
    priority3SlotKey = null;
  }

  void clearSectorSelection() {
    selectedSectorId = null;
    selectedSectorName = null;
  }

  void clearBillingSelection() {
    selectedBill = null;
    selectedBillCountType = null;
    selectedBillModel = null;
    selectedBasicStandard = 0;
    selectedBasicAmount = 0;
    selectedAddStandard = 0;
    selectedAddAmount = 0;
    selectedRegularAmount = 0;
    selectedRegularDurationHours = 0;
  }

  ModifyPlateController({
    required this.context,
    required this.plate,
    required this.collectionKey,
    required this.capabilityArea,
    required this.canUseBill,
    required this.canUseSector,
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

    final initialRegion = plate.region?.trim() ?? '';
    dropdownValue = initialRegion.isEmpty ? '전국' : initialRegion;
    locationController.text = plate.location;

    selectedBill = plate.billingType;
    selectedBillType = _determineBillType();
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

  String _determineBillType() {
    final explicitPlan = (plate.billingPlanType ?? '').trim();
    if (explicitPlan == '정기') return '정기';
    if (explicitPlan == '변동') return '변동';
    if ((plate.regularAmount ?? 0) > 0) return '정기';
    final billingType = (plate.billingType ?? '').trim();
    if (billingType.contains('정기')) return '정기';
    return '변동';
  }

  Future<void> resolveStatusContext() async {
    final repo = context.read<PlateRepository>();
    final monthlyLookup = await repo.lookupPlateStatus(
      plateNumber: plate.plateNumber,
      area: plate.area,
      scope: PlateStatusScope.monthly,
    );

    if (monthlyLookup.isFailed) {
      throw PlateStatusReadException(
        '상태 메모 최신 정보를 확인하지 못했습니다.',
        cause: monthlyLookup.error,
      );
    }

    late final PlateStatusScope scope;
    late final PlateStatusLookupResult lookup;

    if (monthlyLookup.isFound) {
      scope = PlateStatusScope.monthly;
      lookup = monthlyLookup;
    } else if (monthlyLookup.isInactive) {
      scope = PlateStatusScope.history;
      lookup = await repo.lookupPlateStatus(
        plateNumber: plate.plateNumber,
        area: plate.area,
        scope: PlateStatusScope.history,
      );
    } else if ((canUseBill ? selectedBillType : _determineBillType()) == '정기') {
      scope = PlateStatusScope.monthly;
      lookup = monthlyLookup;
    } else {
      scope = PlateStatusScope.history;
      lookup = await repo.lookupPlateStatus(
        plateNumber: plate.plateNumber,
        area: plate.area,
        scope: PlateStatusScope.history,
      );
    }

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
      'memoLength=${authoritativeDraft.customStatus.length} '
      'monthlyLookup=${monthlyLookup.state.name}',
    );
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
      selectedBillType = '정기';
      selectedRegularAmount = bill.regularAmount;
      selectedRegularDurationHours = bill.regularDurationValue;
      selectedBasicAmount = 0;
      selectedBasicStandard = 0;
      selectedAddAmount = 0;
      selectedAddStandard = 0;
    }
  }

  Future<bool> _revalidateBillingFromLocalCache({
    DeveloperOperationTrace? trace,
  }) async {
    if (!canUseBill) return true;

    final normalizedSelectedBill = selectedBill?.trim();
    selectedBill =
        normalizedSelectedBill == null || normalizedSelectedBill.isEmpty
            ? null
            : normalizedSelectedBill;

    if (selectedBill == null) {
      trace?.log('billing_local_validation=cleared');
      debugPrint(
        '[ModifyPlateController][Billing] source=local state=cleared',
      );
      return true;
    }

    final billState = context.read<BillState>();
    if (billState.isLoading) {
      trace?.log('billing_local_validation=cache_reload');
      await billState.loadFromBillCache();
    }
    dynamic matched;
    if (selectedBillType == '정기') {
      for (final bill in billState.regularBills) {
        if (bill.countType.trim() == selectedBill) {
          matched = bill;
          break;
        }
      }
    } else {
      for (final bill in billState.generalBills) {
        if (bill.countType.trim() == selectedBill) {
          matched = bill;
          break;
        }
      }
    }

    if (matched == null) {
      trace?.log(
        'billing_local_validation=failed plan=$selectedBillType value=${selectedBill ?? ''}',
      );
      debugPrint(
        '[ModifyPlateController][Billing] source=local state=missing '
        'plan=$selectedBillType value=${selectedBill ?? ''}',
      );
      if (context.mounted) {
        showFailedSnackbar(
          context,
          '선택한 정산 정보를 로컬에서 확인할 수 없습니다.',
          useCommonUi: true,
        );
      }
      return false;
    }

    applyBillDefaults(matched);
    trace?.log(
      'billing_local_validation=ready plan=$selectedBillType value=${selectedBill ?? ''} '
      'basic=$selectedBasicStandard/$selectedBasicAmount '
      'add=$selectedAddStandard/$selectedAddAmount '
      'regular=$selectedRegularDurationHours/$selectedRegularAmount',
    );
    debugPrint(
      '[ModifyPlateController][Billing] source=local state=ready '
      'plan=$selectedBillType value=${selectedBill ?? ''} '
      'basic=$selectedBasicStandard/$selectedBasicAmount '
      'add=$selectedAddStandard/$selectedAddAmount '
      'regular=$selectedRegularDurationHours/$selectedRegularAmount',
    );
    return true;
  }

  Future<PlateModel?> handleAction({
    DeveloperOperationTrace? trace,
  }) async {
    trace?.log('수정 처리 시작');

    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea.trim();
    final currentCapabilities = areaState.capabilitiesOfCurrentArea;
    final currentHasBill = currentCapabilities.contains(Capability.bill);
    final currentHasSector = currentCapabilities.contains(Capability.sector);

    trace?.log(
      'modify_capabilities snapshotArea=$capabilityArea currentArea=$currentArea '
      'bill=$canUseBill/$currentHasBill sector=$canUseSector/$currentHasSector',
    );
    debugPrint(
      '[ModifyPlateController][Capabilities] snapshotArea=$capabilityArea '
      'currentArea=$currentArea bill=$canUseBill/$currentHasBill '
      'sector=$canUseSector/$currentHasSector',
    );

    if (currentArea != capabilityArea.trim() ||
        currentHasBill != canUseBill ||
        currentHasSector != canUseSector) {
      trace?.log('중단: 지역 capability 변경 감지');
      if (context.mounted) {
        showFailedSnackbar(
          context,
          '지역 기능 설정이 변경되어 저장하지 않았습니다. 수정 화면을 다시 열어 주세요.',
          useCommonUi: true,
        );
      }
      return null;
    }

    if (!await _revalidateBillingFromLocalCache(trace: trace)) {
      return null;
    }

    final effectiveSectorId = canUseSector ? selectedSectorId : plate.sectorId;
    final effectiveSectorName =
        canUseSector ? selectedSectorName : plate.sectorName;
    final statusChangedBeforeResolve = hasStatusChanges;

    if (statusChangedBeforeResolve && !statusContextResolved) {
      try {
        trace?.log('status_context=resolve_required reason=status_changed');
        await resolveStatusContext();
      } catch (error) {
        trace?.log('중단: 상태 저장 범위 확인 실패 error=$error');
        if (context.mounted) {
          showFailedSnackbar(
            context,
            '상태 메모 최신 정보를 확인하지 못해 저장하지 않았습니다.',
            useCommonUi: true,
          );
        }
        return null;
      }
    } else if (!statusChangedBeforeResolve) {
      trace?.log('status_context=skip reason=status_unchanged');
    }

    final draft = statusDraft;
    final statusChanged = hasStatusChanges;
    final resolvedScope = statusScope;
    if (statusChanged && resolvedScope == null) {
      trace?.log('중단: 상태 저장 범위 없음');
      return null;
    }

    final userState = context.read<UserState>();
    final scopeLabel = resolvedScope?.storageLabel ?? 'skipped';

    trace?.log(
      'status memoLength=${draft.customStatus.length} '
      'changed=$statusChanged deletePending=$statusMarkedForDeletion '
      'scope=$scopeLabel',
    );
    debugPrint(
      '[ModifyPlateController][Status] plate=${plate.plateNumber} '
      'memoLength=${draft.customStatus.length} '
      'changed=$statusChanged deletePending=$statusMarkedForDeletion '
      'scope=$scopeLabel',
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
      selectedBillType: selectedBillType == '정기' ? '정기' : '변동',
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
      canUseBill: canUseBill,
      canUseSector: canUseSector,
      statusScope: resolvedScope,
      statusChanged: statusChanged,
      expectedOriginalStatus: expectedPersistedStatusDraft,
      expectedStatusSourcePath: expectedStatusSourcePath,
      statusActorId: userState.session?.id ?? '',
      statusActorName: userState.name.trim(),
      onDebug: trace == null ? null : (message) => trace.log(message),
    );

    final plateNumber = service.composePlateNumber();
    final newLocation = locationController.text.trim();
    final newBillingType = canUseBill ? selectedBill : plate.billingType;
    final updatedCustomStatus = draft.customStatus;

    trace?.log('plateNumber=$plateNumber');
    trace?.log('newLocation="$newLocation"');
    trace?.log(
      'capability.bill=$canUseBill capability.sector=$canUseSector '
      'sectorId=${effectiveSectorId ?? ''} '
      'sectorName=${effectiveSectorName ?? ''}',
    );
    debugPrint(
      '[ModifyPlateController][Capabilities] plate=$plateNumber area=${plate.area} '
      'capability.bill=$canUseBill capability.sector=$canUseSector '
      'sectorId=${effectiveSectorId ?? ''} '
      'sectorName=${effectiveSectorName ?? ''}',
    );

    ModifyPhotoUploadResult? uploadResult;
    var firestoreCommitted = false;

    Future<void> cleanupUploadedImages(String reason) async {
      final paths = uploadResult?.uploadedObjectPaths ?? const <String>[];
      if (paths.isEmpty || firestoreCommitted) return;
      trace?.log(
        'photo_cleanup=start reason=$reason count=${paths.length}',
      );
      final failedPaths = await ModifyPlateService.cleanupUploadedImages(
        paths,
        onDebug: trace == null ? null : (message) => trace.log(message),
      );
      trace?.log(
        'photo_cleanup=done reason=$reason requested=${paths.length} failed=${failedPaths.length}',
      );
      debugPrint(
        '[ModifyPlateController][PhotoCleanup] reason=$reason '
        'requested=${paths.length} failed=${failedPaths.length}',
      );
    }

    try {
      trace?.log('사진 병합 업로드 시작');
      uploadResult = await service.uploadAndMergeImages(plateNumber);
      trace?.log(
        '사진 병합 업로드 완료 merged=${uploadResult.mergedUrls.length} '
        'uploaded=${uploadResult.uploadedObjectPaths.length} '
        'failed=${uploadResult.failedFiles.length}',
      );

      trace?.log('차량 정보 업데이트 시작');
      final success = await service.updatePlateInfo(
        plateNumber: plateNumber,
        imageUrls: uploadResult.mergedUrls,
        newLocation: newLocation,
        newBillingType: newBillingType,
        updatedCustomStatus: updatedCustomStatus,
      );
      trace?.log('차량 정보 업데이트 결과=$success');

      if (!success) {
        trace?.log('중단: updatePlateInfo returned false');
        await cleanupUploadedImages('update_returned_false');
        return null;
      }

      firestoreCommitted = true;
      trace?.log(
        statusChanged
            ? '차량 문서와 상태 문서 transaction 저장 완료'
            : '차량 문서 transaction 저장 완료 status=skipped',
      );

      final updatedPlate = PlateModel(
        id: plate.id,
        addAmount: canUseBill ? selectedAddAmount : plate.addAmount,
        addStandard: canUseBill ? selectedAddStandard : plate.addStandard,
        area: plate.area,
        basicAmount: canUseBill ? selectedBasicAmount : plate.basicAmount,
        basicStandard: canUseBill ? selectedBasicStandard : plate.basicStandard,
        billingType: newBillingType,
        billingPlanType: canUseBill
            ? (selectedBillType == '정기' ? '정기' : '변동')
            : plate.billingPlanType,
        customStatus: statusChanged
            ? updatedCustomStatus
            : statusContextResolved
                ? draft.customStatus
                : plate.customStatus,
        endTime: plate.endTime,
        imageUrls: uploadResult.mergedUrls,
        isLockedFee: plate.isLockedFee,
        isSelected: plate.isSelected,
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
        regularAmount:
            canUseBill ? selectedRegularAmount : plate.regularAmount,
        regularDurationValue: canUseBill
            ? selectedRegularDurationHours
            : plate.regularDurationValue,
        requestTime: plate.requestTime,
        selectedBy: plate.selectedBy,
        type: plate.type,
        updatedAt: plate.updatedAt,
        userAdjustment: plate.userAdjustment,
        userName: plate.userName,
        feeMode: plate.feeMode,
        sectorId: effectiveSectorId,
        sectorName: effectiveSectorName,
      );

      final plateState = context.read<DoublePlateState>();
      trace?.log('로컬 상태 반영 시작');
      await plateState.doubleUpdatePlateLocally(collectionKey, updatedPlate);
      trace?.log('로컬 상태 반영 완료');
      trace?.log('수정 처리 성공');
      return updatedPlate;
    } catch (e, st) {
      if (!firestoreCommitted) {
        await cleanupUploadedImages('update_exception');
      }
      trace?.log('예외 발생: $e');
      final compactStack = st
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(6)
          .join(' | ');
      if (compactStack.isNotEmpty) {
        trace?.log(compactStack);
      }
      if (context.mounted) {
        showFailedSnackbar(
          context,
          '수정 처리 실패: $e',
          useCommonUi: true,
        );
      }
      return null;
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
