import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/location/applications/location_state.dart';
import '../../../../features/payment/applications/bill_state.dart';
import '../../../../features/payment/domain/models/bill_model.dart';
import '../../../../features/payment/domain/models/regular_bill_model.dart';
import '../../../../features/sector/domain/models/sector_model.dart';
import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/models/plate_model.dart';
import '../../../plate/editor/domain/plate_editor_workspace.dart';
import '../../../plate/editor/domain/plate_parking_display.dart';
import '../controllers/modify_plate_controller.dart';
import '../../../plate/editor/workspaces/plate_camera_workspace.dart';
import '../../../plate/editor/widgets/plate_editor_footer.dart';
import '../../../plate/editor/widgets/plate_editor_rail.dart';
import '../../../plate/editor/workspaces/plate_billing_workspace.dart';
import '../../../plate/editor/workspaces/plate_memo_workspace.dart';
import 'workspaces/modify_overview_workspace.dart';
import 'widgets/modify_photo_section.dart';
import 'sheets/modify_region_picker_bottom_sheet.dart';
import '../../../plate/editor/widgets/plate_parking_picker_content.dart';
import '../../../plate/editor/workspaces/plate_sector_workspace.dart';
import '../../../plate/editor/dialogs/plate_editor_dialog.dart';

Future<PlateModel?> showModifyPlateSideDock({
  required BuildContext context,
  required PlateModel plate,
  required PlateType collectionKey,
  bool isMinorMode = false,
}) async {
  final trace = await DeveloperOperationTrace.start(
    context: context,
    title: '차량 정보 수정 · ${plate.plateNumber}',
    initialMessage: '차량 정보 수정 Side Dock을 준비합니다.',
    useCommonUi: true,
    developerModeMessage:
        '개발자 모드 ON: 수정 흐름의 debugPrint 코드를 Status Dialog에서 복사할 수 있습니다.',
    standardModeMessage: '개발자 모드 OFF: 수정 흐름을 콘솔에 기록합니다.',
    showDialogImmediately: false,
  );

  if (!context.mounted) return null;

  trace.log(
    'modify_side_dock=open direction=right_to_left maxWidth=360 widthFactor=0.92 barrierDismissible=false plate=${plate.plateNumber}',
    progress: .08,
  );

  try {
    final result = await showCommonRightSideDock<PlateModel>(
      context: context,
      barrierLabel: '차량 정보 수정',
      maxWidth: 360,
      widthFactor: .92,
      barrierDismissible: false,
      builder: (dockContext) {
        return ModifyPlateScreen(
          plate: plate,
          collectionKey: collectionKey,
          isMinorMode: isMinorMode,
          trace: trace,
        );
      },
    );

    trace.log(
      'modify_side_dock=closed saved=${result != null} resultPlate=${result?.plateNumber ?? plate.plateNumber}',
      progress: .96,
    );
    await trace.succeed(
      result == null ? '차량 정보 수정 Side Dock이 닫혔습니다.' : '차량 정보 수정 저장이 완료되었습니다.',
    );
    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }
    return result;
  } catch (error, stackTrace) {
    await trace.fail(
      '차량 정보 수정 Side Dock 처리 중 예외가 발생했습니다.',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      showFailedSnackbar(
        context,
        '차량 정보 수정 화면을 열지 못했습니다.',
        useCommonUi: true,
      );
    }
    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }
    return null;
  }
}

class ModifyPlateScreen extends StatefulWidget {
  const ModifyPlateScreen({
    super.key,
    required this.plate,
    required this.collectionKey,
    this.isMinorMode = false,
    this.trace,
  });

  final PlateModel plate;
  final PlateType collectionKey;
  final bool isMinorMode;
  final DeveloperOperationTrace? trace;

  @override
  State<ModifyPlateScreen> createState() => _ModifyPlateScreenState();
}

class _ModifyPlateScreenState extends State<ModifyPlateScreen> {
  late final ModifyPlateController _controller;

  final TextEditingController controllerFrontdigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController _memoDraftController = TextEditingController();
  final List<XFile> _capturedImages = <XFile>[];
  final List<String> _existingImageUrls = <String>[];

  bool isLoading = false;
  bool _statusContextResolving = false;
  String? _statusContextError;
  PlateEditorWorkspace? _activeDialog;
  late String _policySignature;
  bool _memoPending = false;
  int _cameraSessionKey = 0;
  bool _cameraStartInPreview = false;
  List<dynamic> _cameraInitialPreviewImages = const <dynamic>[];
  int _cameraInitialPreviewIndex = 0;

  bool get _busy => isLoading || _statusContextResolving;

  bool _isBillingWorkspace(PlateEditorWorkspace workspace) {
    return workspace == PlateEditorWorkspace.variableBilling ||
        workspace == PlateEditorWorkspace.regularBilling;
  }

  bool _isMonthlyLockedWorkspace(PlateEditorWorkspace workspace) {
    return _isBillingWorkspace(workspace) ||
        workspace == PlateEditorWorkspace.memo;
  }

  Set<PlateEditorWorkspace> get _disabledMonthlyWorkspaces =>
      _controller.billingLocked
          ? const <PlateEditorWorkspace>{
              PlateEditorWorkspace.variableBilling,
              PlateEditorWorkspace.regularBilling,
              PlateEditorWorkspace.memo,
            }
          : const <PlateEditorWorkspace>{};
  bool get _hasPendingWorkspaceDraft => _memoPending;

  @override
  void initState() {
    super.initState();
    final areaState = context.read<AreaState>();
    final policy = PlateEditorPolicy.fromCapabilities(
      area: areaState.currentArea,
      capabilities: areaState.capabilitiesOfCurrentArea,
    );
    _policySignature = policy.signature;
    _controller = ModifyPlateController(
      context: context,
      plate: widget.plate,
      collectionKey: widget.collectionKey,
      controllerFrontdigit: controllerFrontdigit,
      controllerMidDigit: controllerMidDigit,
      controllerBackDigit: controllerBackDigit,
      locationController: locationController,
      capturedImages: _capturedImages,
      existingImageUrls: _existingImageUrls,
      capabilityArea: policy.area,
      canUseBill: policy.hasBill,
      canUseSector: policy.hasSector,
    );
    _controller.initializePlate();
    _controller.initializeFieldValues();
    _memoDraftController.text = _controller.customStatusController.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _log(
        'modify_dock=mounted plate=${widget.plate.plateNumber} area=${widget.plate.area}',
        progress: .14,
      );
      _log(
        'modify_capabilities area=${policy.area} bill=${policy.hasBill} sector=${policy.hasSector} billingLocked=${_controller.billingLocked}',
        progress: .16,
      );
      _log(
        'identity_edit_policy plateEditable=false regionEditable=true',
        progress: .165,
      );
      _log('overview=ready display=list_surface editMode=central', progress: .17);
      _log(
        'regular_billing_ui=read_only rail=hidden contentLabel=정기 등록 railVariableLabel=정산',
        progress: .172,
      );
      _log(
        'content_status_labels required=필수 입력 optional=선택 입력 complete=입력 완료 minorParkingOptional=${widget.isMinorMode}',
        progress: .174,
      );
      _log('status_context=lazy_ready trigger=memo_or_status_change', progress: .18);
    });
  }

  void _log(String message, {double? progress}) {
    final trace = widget.trace;
    if (trace != null) {
      trace.log(message, progress: progress);
      return;
    }
    debugPrint('[ModifyPlateDock] $message');
  }

  String get _pendingMessage {
    if (_memoPending) return '상태 메모 변경을 먼저 적용하세요';
    return '';
  }

  Future<void> _openRegionPicker({String source = 'overview_region'}) async {
    if (!mounted || _busy || _activeDialog != null) {
      _log(
        'identity_region=open_skipped source=$source busy=$_busy dialog=${_activeDialog?.name ?? 'none'}',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    _log(
      'identity_region=picker_open source=$source current=${_controller.dropdownValue}',
    );
    await modifyRegionPickerBottomSheet(
      context: context,
      selectedRegion: _controller.dropdownValue,
      regions: _controller.regions,
      onConfirm: (selected) {
        if (!mounted) return;
        final next = selected.trim();
        if (next.isEmpty) return;
        final previous = _controller.dropdownValue;
        if (previous == next) {
          _log(
            'identity_region=unchanged source=$source region=$next',
          );
          return;
        }
        setState(() => _controller.dropdownValue = next);
        HapticFeedback.selectionClick();
        _log(
          'identity_region=applied source=$source previous=$previous current=$next plate=${_controller.currentPlateNumberDisplay}',
        );
      },
    );
  }

  Future<void> _showDeveloperStatus() async {
    final trace = widget.trace;
    if (trace == null || !trace.developerMode || !mounted) return;
    _log('developer_status_dialog=open source=header_action');
    await trace.showSnapshotStatusDialog(
      context,
      title: '차량 정보 수정 디버그 상태',
      description: '현재까지 기록된 수정 흐름을 확인합니다.',
    );
  }

  Future<void> _resolveStatusContext() async {
    if (!mounted) return;
    setState(() {
      _statusContextResolving = true;
      _statusContextError = null;
    });
    _log(
      'status_context=resolve_start plate=${widget.plate.plateNumber}',
      progress: .2,
    );

    try {
      await _controller.resolveStatusContext();
      if (!mounted) return;
      setState(() {
        _statusContextResolving = false;
        _statusContextError = null;
        if (!_memoPending) {
          _memoDraftController.text = _controller.customStatusController.text;
        }
      });
      _log(
        'status_context=resolved scope=${_controller.statusScope?.name ?? 'none'} sourcePath=${_controller.expectedStatusSourcePath ?? ''}',
        progress: .3,
      );
    } catch (error, stackTrace) {
      _log(
        'status_context=resolve_failed plate=${widget.plate.plateNumber} error=$error',
        progress: .3,
      );
      if (!mounted) return;
      setState(() {
        _statusContextResolving = false;
        _statusContextError = error.toString();
      });
      final trace = widget.trace;
      if (trace != null && trace.developerMode && mounted) {
        await trace.showSnapshotStatusDialog(
          context,
          title: '상태 저장 범위 확인 실패',
          description: '상태 저장 범위를 확인하지 못했습니다.',
          failure: true,
        );
      }
      _log('status_context=stack_trace\n$stackTrace');
    }
  }

  PlateEditorDialogSize _dialogSize(PlateEditorWorkspace workspace) {
    switch (workspace) {
      case PlateEditorWorkspace.parking:
        return PlateEditorDialogSize.wide;
      case PlateEditorWorkspace.camera:
        return PlateEditorDialogSize.immersive;
      case PlateEditorWorkspace.vehicleIdentity:
      case PlateEditorWorkspace.sector:
      case PlateEditorWorkspace.variableBilling:
      case PlateEditorWorkspace.regularBilling:
      case PlateEditorWorkspace.memo:
        return PlateEditorDialogSize.standard;
      case PlateEditorWorkspace.overview:
        return PlateEditorDialogSize.compact;
    }
  }

  String _dialogLabel(PlateEditorWorkspace workspace) {
    switch (workspace) {
      case PlateEditorWorkspace.vehicleIdentity:
        return '차량 정보';
      case PlateEditorWorkspace.parking:
        return '주차 위치';
      case PlateEditorWorkspace.camera:
        return '차량 촬영';
      case PlateEditorWorkspace.sector:
        return '방문 구역';
      case PlateEditorWorkspace.variableBilling:
        return '변동 정산';
      case PlateEditorWorkspace.regularBilling:
        return '정기 정산';
      case PlateEditorWorkspace.memo:
        return '상태 메모';
      case PlateEditorWorkspace.overview:
        return '차량 정보';
    }
  }

  void _syncPolicy(PlateEditorPolicy policy) {
    if (_policySignature == policy.signature) return;
    final previousSignature = _policySignature;
    _policySignature = policy.signature;
    _log(
      'capabilities=changed previous=$previousSignature current=${policy.signature}',
    );
    final active = _activeDialog;
    if (active != null && !policy.supports(active)) {
      _log('dialog=${active.name}_capability_invalidated');
    }
  }

  Future<void> _openEditorDialog(
    PlateEditorWorkspace workspace,
    PlateEditorPolicy policy, {
    String source = 'rail',
    List<dynamic> previewImages = const <dynamic>[],
    int previewIndex = 0,
  }) async {
    if (_busy || _activeDialog != null) return;
    if (workspace == PlateEditorWorkspace.overview || !policy.supports(workspace)) {
      return;
    }
    if (workspace == PlateEditorWorkspace.regularBilling) {
      _log(
        'workspace=ignored reason=regular_billing_read_only source=$source',
      );
      return;
    }
    if (_controller.billingLocked &&
        _isMonthlyLockedWorkspace(workspace)) {
      _log(
        'workspace=blocked reason=monthly_parking workspace=${workspace.name} source=$source',
      );
      return;
    }
    if (workspace == PlateEditorWorkspace.vehicleIdentity) {
      _log('identity_plate=edit_blocked source=$source plate=${_controller.currentPlateNumberDisplay}');
      return;
    }
    if (workspace == PlateEditorWorkspace.memo && !_memoPending) {
      _memoDraftController.text = _controller.customStatusController.text;
    }
    if (workspace == PlateEditorWorkspace.camera) {
      _cameraSessionKey++;
      _cameraStartInPreview = previewImages.isNotEmpty;
      _cameraInitialPreviewImages = List<dynamic>.from(previewImages);
      _cameraInitialPreviewIndex = previewImages.isEmpty
          ? 0
          : previewIndex.clamp(0, previewImages.length - 1).toInt();
    }
    setState(() => _activeDialog = workspace);
    _log('dialog=${workspace.name}_open source=$source');
    try {
      await showPlateEditorDialog<void>(
        context: context,
        barrierLabel: _dialogLabel(workspace),
        size: _dialogSize(workspace),
        barrierDismissible: false,
        builder: (dialogContext) => _buildDialogContent(
          dialogContext,
          workspace,
        ),
      );
    } finally {
      if (mounted && _activeDialog == workspace) {
        setState(() => _activeDialog = null);
      }
      _log('dialog=${workspace.name}_close');
    }
  }

  void _applyParking(String location) {
    final previous = _controller.locationController.text.trim();
    final normalized = location.trim();
    final locations = context.read<LocationState>().locations;
    final isTower = plateParkingLocationIsTower(
      normalized,
      locations: locations,
    );
    final displayLocation = plateParkingOverviewLocation(
      normalized,
      locations: locations,
    );
    setState(() {
      _controller.locationController.text = normalized;
      _controller.isLocationSelected = true;
    });
    _log('parking_location=auto_applied previous=$previous selected=$normalized');
    _log(
      'parking_display=resolved tower=$isTower internal=$normalized visible=$displayLocation towerSlotVisibility=${isTower ? 'hidden' : 'visible'}',
    );
  }

  Future<void> _applySector(SectorModel sector) async {
    final previousId = _controller.selectedSectorId?.trim() ?? '';
    final previousName = _controller.selectedSectorName?.trim() ?? '';
    setState(() {
      _controller.selectedSectorId = sector.id.trim();
      _controller.selectedSectorName = sector.name.trim();
    });
    _log(
      'sector=selected previousSectorId=$previousId previousSectorName=$previousName selectedSectorId=${sector.id.trim()} selectedSectorName=${sector.name.trim()}',
    );
  }

  void _applyMemo(String value) {
    if (_controller.billingLocked) {
      _log('memo=blocked reason=monthly_parking action=apply');
      return;
    }
    setState(() {
      _controller.customStatusController.text = value;
      _controller.handleStatusTextChanged();
      _memoPending = false;
    });
    HapticFeedback.selectionClick();
    _log('memo=applied length=${value.trim().length}');
  }

  Future<bool> _confirmDiscard() async {
    final result = await showCommonOverlayDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('수정 취소'),
          content: Text(
            _hasPendingWorkspaceDraft
                ? '아직 적용하지 않은 작업과 저장하지 않은 변경 내용을 모두 버리고 닫을까요?'
                : '변경 내용을 저장하지 않고 닫을까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('계속 수정'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _requestClose({String source = 'header_close'}) async {
    if (_busy || !mounted) return;
    final dirty = _controller.hasUnsavedChanges || _hasPendingWorkspaceDraft;
    _log(
      'close=request source=$source dirty=$dirty pendingWorkspace=$_hasPendingWorkspaceDraft',
    );
    if (dirty && !await _confirmDiscard()) {
      _log('close=cancelled source=$source');
      return;
    }
    if (!mounted) return;
    _log('close=confirmed source=$source');
    Navigator.of(context).pop();
  }

  Future<void> _handleModifyAction() async {
    if (_busy || _hasPendingWorkspaceDraft) return;

    final statusChanged = _controller.hasStatusChanges;
    if (statusChanged &&
        (_statusContextError != null || !_controller.statusContextResolved)) {
      _log('status_context=save_resolve_required reason=status_changed');
      await _resolveStatusContext();
      if (!mounted ||
          _statusContextError != null ||
          !_controller.statusContextResolved) {
        return;
      }
    } else if (!statusChanged) {
      _log('status_context=save_skip reason=status_unchanged');
    }

    setState(() => isLoading = true);
    _log(
      'change_summary identity=${_controller.hasVehicleIdentityChanges} parking=${_controller.hasLocationChanges} photo=${_controller.hasPhotoChanges} sector=${_controller.hasSectorChanges} billing=${_controller.hasBillingChanges} memo=${_controller.hasStatusChanges} count=${_controller.changeCount}',
      progress: .4,
    );
    _log(
      'save=start plate=${widget.plate.plateNumber} dirty=${_controller.hasUnsavedChanges} changeCount=${_controller.changeCount}',
      progress: .42,
    );

    try {
      final updatedPlate = await _controller.handleAction(trace: widget.trace);
      if (!mounted) return;

      if (updatedPlate == null) {
        _log('save=failed result=null', progress: .82);
        final trace = widget.trace;
        if (trace != null && trace.developerMode && mounted) {
          await trace.showSnapshotStatusDialog(
            context,
            title: '차량 정보 수정 저장 실패',
            description: '저장 결과를 확인하지 못했습니다.',
            failure: true,
          );
        }
        return;
      }

      _log(
        'save=success plate=${updatedPlate.plateNumber} location=${updatedPlate.location} sectorId=${updatedPlate.sectorId ?? ''} sectorName=${updatedPlate.sectorName ?? ''}',
        progress: .9,
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pop(updatedPlate);
    } catch (error, stackTrace) {
      _log('save=exception error=$error', progress: .82);
      _log('save=stack_trace\n$stackTrace');
      if (mounted) {
        showFailedSnackbar(
          context,
          '수정 실패: $error',
          useCommonUi: true,
        );
      }
      final trace = widget.trace;
      if (trace != null && trace.developerMode && mounted) {
        await trace.showSnapshotStatusDialog(
          context,
          title: '차량 정보 수정 저장 예외',
          description: '저장 중 예외가 발생했습니다.',
          failure: true,
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _closeForInvalidParkingConfiguration(
    BuildContext dialogContext,
  ) async {
    _log(
      'parking_configuration=invalid reason=mixed_location_types action=close_modify_side_dock',
    );
    final navigator = Navigator.of(dialogContext, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 190));
    }
    if (!mounted) return;
    _log(
      'close=forced source=parking_mixed_configuration discardPrompt=false',
    );
    Navigator.of(context).pop();
  }

  void _closeEditorDialog(
    BuildContext dialogContext,
    PlateEditorWorkspace workspace, {
    required String reason,
  }) {
    _log('dialog=${workspace.name}_request_close reason=$reason');
    Navigator.of(dialogContext, rootNavigator: true).pop();
  }

  void _clearOverviewParking() {
    final previousLocation = _controller.locationController.text.trim();
    final previousPriorities = _controller.selectedParkingPriorities.join('|');
    setState(() {
      _controller.clearParkingSelection();
    });
    HapticFeedback.selectionClick();
    _log(
      'overview=row_tap workspace=parking action=clear previousLocation=$previousLocation previousPriorities=$previousPriorities',
    );
  }

  void _clearOverviewSector() {
    final previousId = _controller.selectedSectorId?.trim() ?? '';
    final previousName = _controller.selectedSectorName?.trim() ?? '';
    setState(_controller.clearSectorSelection);
    HapticFeedback.selectionClick();
    _log(
      'overview=row_tap workspace=sector action=clear previousSectorId=$previousId previousSectorName=$previousName',
    );
  }

  void _clearOverviewBilling(PlateEditorWorkspace workspace) {
    if (_controller.billingLocked) {
      _log('billing=clear_blocked reason=monthly_parking workspace=${workspace.name}');
      return;
    }
    final targetType = workspace == PlateEditorWorkspace.regularBilling
        ? '정기'
        : '변동';
    final previousType = _controller.selectedBillType;
    final previousValue =
        _controller.selectedBillCountType?.trim().isNotEmpty == true
            ? _controller.selectedBillCountType!.trim()
            : _controller.selectedBill?.trim() ?? '';
    setState(() {
      _controller.clearBillingSelection();
      _controller.selectedBillType = targetType;
      _controller.invalidateStatusContext();
      _statusContextError = null;
      _statusContextResolving = false;
    });
    HapticFeedback.selectionClick();
    _log(
      'overview=row_tap workspace=${workspace.name} action=clear targetType=$targetType previousType=$previousType previousValue=$previousValue',
    );
  }

  Future<void> _handleOverviewWorkspaceTap(
    PlateEditorWorkspace workspace,
    PlateEditorPolicy policy,
  ) async {
    if (_busy || workspace == PlateEditorWorkspace.overview) return;
    if (!policy.supports(workspace)) return;
    if (_controller.billingLocked &&
        _isMonthlyLockedWorkspace(workspace)) {
      _log(
        'overview=row_tap_blocked workspace=${workspace.name} reason=monthly_parking',
      );
      return;
    }

    switch (workspace) {
      case PlateEditorWorkspace.parking:
        final hasParking =
            _controller.locationController.text.trim().isNotEmpty ||
                _controller.selectedParkingPriorities.isNotEmpty;
        if (hasParking) {
          _clearOverviewParking();
          return;
        }
        break;
      case PlateEditorWorkspace.sector:
        final hasSector =
            _controller.selectedSectorId?.trim().isNotEmpty == true ||
                _controller.selectedSectorName?.trim().isNotEmpty == true;
        if (hasSector) {
          _clearOverviewSector();
          return;
        }
        break;
      case PlateEditorWorkspace.variableBilling:
        if (_controller.selectedBillType == '변동' &&
            _controller.hasBillingSelection) {
          _clearOverviewBilling(workspace);
          return;
        }
        break;
      case PlateEditorWorkspace.regularBilling:
        _log(
          'overview=row_tap_ignored workspace=regularBilling reason=read_only',
        );
        return;
      case PlateEditorWorkspace.vehicleIdentity:
        _log('identity_plate=edit_blocked source=overview_row_tap plate=${_controller.currentPlateNumberDisplay}');
        return;
      case PlateEditorWorkspace.camera:
      case PlateEditorWorkspace.memo:
      case PlateEditorWorkspace.overview:
        break;
    }

    await HapticFeedback.selectionClick();
    _log('overview=row_tap workspace=${workspace.name} action=open');
    await _openEditorDialog(
      workspace,
      policy,
      source: 'overview_row_tap',
    );
  }

  Widget _buildOverview(PlateEditorPolicy policy) {
    return ModifyOverviewWorkspace(
      controller: _controller,
      plate: widget.plate,
      policy: policy,
      statusContextResolving: _statusContextResolving,
      statusContextError: _statusContextError,
      isMinorMode: widget.isMinorMode,
      onRegionTap: () => unawaited(_openRegionPicker()),
      onWorkspaceTap: (workspace) => unawaited(
        _handleOverviewWorkspaceTap(workspace, policy),
      ),
    );
  }

  Widget _buildModifyBillingWorkspace(
    BuildContext dialogContext,
    StateSetter setDialogState,
    PlateEditorWorkspace workspace,
  ) {
    final billState = context.read<BillState>();
    final regular = workspace == PlateEditorWorkspace.regularBilling;
    final targetType = regular ? '정기' : '변동';
    final source = regular
        ? List<dynamic>.from(billState.regularBills)
        : List<dynamic>.from(billState.generalBills);
    final options = source
        .map(
          (bill) => PlateBillingOption(
            value: bill.countType,
            detail: bill is BillModel
                ? '${bill.basicStandard ?? 0}분 · ${bill.basicAmount ?? 0}원 · 추가 ${bill.addStandard ?? 0}분 ${bill.addAmount ?? 0}원'
                : bill is RegularBillModel
                    ? '${bill.regularDurationValue}시간 · ${bill.regularAmount}원'
                    : '',
          ),
        )
        .toList(growable: false);
    final active = _controller.selectedBillType == targetType &&
        _controller.hasBillingSelection;
    final selectedValue = active
        ? (_controller.selectedBillCountType?.trim().isNotEmpty == true
            ? _controller.selectedBillCountType!.trim()
            : _controller.selectedBill?.trim() ?? '')
        : '';

    return PlateBillingWorkspace(
      onExit: () => _closeEditorDialog(
        dialogContext,
        workspace,
        reason: '${workspace.name}_exit',
      ),
      selectedType: targetType,
      selectedValue: selectedValue,
      title: regular ? '정기 정산' : '변동 정산',
      subtitle: targetType,
      valueOptions: options,
      loading: billState.isLoading,
      onValueChanged: (value) {
        if (_controller.billingLocked) {
          _log('billing=value_change_blocked reason=monthly_parking workspace=${workspace.name} value=${value.trim()}');
          return;
        }
        dynamic selected;
        for (final bill in source) {
          if (bill.countType.trim() == value.trim()) {
            selected = bill;
            break;
          }
        }
        if (selected == null) return;
        setState(() {
          _controller.applyBillDefaults(selected);
          _controller.invalidateStatusContext();
          _statusContextError = null;
          _statusContextResolving = false;
        });
        if (dialogContext.mounted) setDialogState(() {});
        HapticFeedback.selectionClick();
        _log(
          'billing=value_selected workspace=${workspace.name} plan=${_controller.selectedBillType} value=${value.trim()}',
        );
      },
      detailRows: !active
          ? const <PlateBillingDetailRow>[]
          : regular
              ? <PlateBillingDetailRow>[
                  const PlateBillingDetailRow(
                    label: '정산 유형',
                    value: '정기',
                  ),
                  PlateBillingDetailRow(
                    label: '적용 기준',
                    value: selectedValue,
                  ),
                  PlateBillingDetailRow(
                    section: '정기',
                    label: '시간',
                    value: '${_controller.selectedRegularDurationHours}시간',
                  ),
                  PlateBillingDetailRow(
                    label: '금액',
                    value: '${_controller.selectedRegularAmount}원',
                  ),
                ]
              : <PlateBillingDetailRow>[
                  const PlateBillingDetailRow(
                    label: '정산 유형',
                    value: '변동',
                  ),
                  PlateBillingDetailRow(
                    label: '적용 기준',
                    value: selectedValue,
                  ),
                  PlateBillingDetailRow(
                    section: '기본',
                    label: '시간',
                    value: '${_controller.selectedBasicStandard}분',
                  ),
                  PlateBillingDetailRow(
                    label: '금액',
                    value: '${_controller.selectedBasicAmount}원',
                  ),
                  PlateBillingDetailRow(
                    section: '추가',
                    label: '시간',
                    value: '${_controller.selectedAddStandard}분',
                  ),
                  PlateBillingDetailRow(
                    label: '금액',
                    value: '${_controller.selectedAddAmount}원',
                  ),
                ],
    );
  }

  Widget _buildDialogContent(
    BuildContext dialogContext,
    PlateEditorWorkspace workspace,
  ) {
    switch (workspace) {
      case PlateEditorWorkspace.overview:
        return const SizedBox.shrink();
      case PlateEditorWorkspace.vehicleIdentity:
        return const SizedBox.shrink();
      case PlateEditorWorkspace.parking:
        return PlateParkingPickerContent(
          currentLocation: _controller.locationController.text.trim(),
          preferredParkingAreas: _controller.selectedParkingPriorities,
          onLocationApplied: _applyParking,
          onExit: () => _closeEditorDialog(
            dialogContext,
            PlateEditorWorkspace.parking,
            reason: 'parking_exit',
          ),
          onInvalidAreaConfiguration: () {
            unawaited(
              _closeForInvalidParkingConfiguration(dialogContext),
            );
          },
          onDebug: _log,
        );
      case PlateEditorWorkspace.camera:
        return PlateCameraWorkspace(
          key: ValueKey<int>(_cameraSessionKey),
          plateNumber: widget.plate.plateNumber,
          initialCapturedImages: List<XFile>.from(_controller.capturedImages),
          initialPreviewImages: _cameraInitialPreviewImages,
          initialPreviewIndex: _cameraInitialPreviewIndex,
          startInPreview: _cameraStartInPreview,
          onExit: () => _closeEditorDialog(
            dialogContext,
            PlateEditorWorkspace.camera,
            reason: 'camera_exit',
          ),
          onImageCaptured: (image) {
            if (_controller.capturedImages
                .any((item) => item.path == image.path)) {
              return;
            }
            setState(() => _controller.capturedImages.add(image));
            _log(
              'camera=captured path=${image.path} count=${_controller.capturedImages.length}',
            );
          },
          onImageDeleted: (image) {
            setState(() {
              _controller.capturedImages.removeWhere(
                (candidate) => candidate.path == image.path,
              );
            });
            _log(
              'camera=deleted path=${image.path} count=${_controller.capturedImages.length}',
            );
          },
          savedPhotosBuilder: (context, onBack) => ModifySavedPhotosContent(
            plateNumber: widget.plate.plateNumber,
            onBack: onBack,
            onDebug: _log,
          ),
          onDebug: _log,
        );
      case PlateEditorWorkspace.sector:
        return PlateSectorWorkspace(
          selectedId: _controller.selectedSectorId,
          selectedName: _controller.selectedSectorName,
          onSelected: (sector) async {
            await _applySector(sector);
            if (!dialogContext.mounted) return;
            _closeEditorDialog(
              dialogContext,
              PlateEditorWorkspace.sector,
              reason: 'sector_applied',
            );
          },
          onExit: () => _closeEditorDialog(
            dialogContext,
            PlateEditorWorkspace.sector,
            reason: 'sector_exit',
          ),
          onDebug: _log,
        );
      case PlateEditorWorkspace.variableBilling:
      case PlateEditorWorkspace.regularBilling:
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return _buildModifyBillingWorkspace(
              dialogContext,
              setDialogState,
              workspace,
            );
          },
        );
      case PlateEditorWorkspace.memo:
        var initialResolveScheduled = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final unresolved = !_controller.statusContextResolved &&
                _statusContextError == null;
            if (unresolved &&
                !_statusContextResolving &&
                !initialResolveScheduled) {
              initialResolveScheduled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!dialogContext.mounted) return;
                final future = _resolveStatusContext();
                setDialogState(() {});
                await future;
                if (dialogContext.mounted) setDialogState(() {});
              });
            }

            Future<void> retryStatus() async {
              if (!dialogContext.mounted) return;
              final future = _resolveStatusContext();
              setDialogState(() {});
              await future;
              if (dialogContext.mounted) setDialogState(() {});
            }

            return PlateMemoWorkspace(
              controller: _memoDraftController,
              originalValue: _controller.originalStatusDraft.customStatus,
              committedValue: _controller.customStatusController.text,
              statusResolving: _statusContextResolving || unresolved,
              statusError: _statusContextError,
              onRetry: retryStatus,
              onApplied: (value) {
                _applyMemo(value);
                if (!dialogContext.mounted) return;
                _closeEditorDialog(
                  dialogContext,
                  PlateEditorWorkspace.memo,
                  reason: 'memo_applied',
                );
              },
              onPendingChanged: (pending) {
                if (_memoPending == pending) return;
                setState(() => _memoPending = pending);
              },
              onExit: () => _closeEditorDialog(
                dialogContext,
                PlateEditorWorkspace.memo,
                reason: 'memo_exit',
              ),
              onDebug: _log,
            );
          },
        );
    }
  }

  @override
  void dispose() {
    _memoDraftController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final policy = PlateEditorPolicy.fromCapabilities(
      area: areaState.currentArea,
      capabilities: areaState.capabilitiesOfCurrentArea,
    );
    _syncPolicy(policy);
    final dirty = _controller.hasUnsavedChanges;
    final pending = _hasPendingWorkspaceDraft;
    final busy = _busy;
    final footerMessage = pending
        ? _pendingMessage
        : dirty
            ? '변경 ${_controller.changeCount}개'
            : '변경 사항 없음';
    final headerPlateNumber = _controller.currentPlateNumberDisplay.trim().isEmpty
        ? widget.plate.plateNumber
        : _controller.currentPlateNumberDisplay;

    return PopScope(
      canPop: !busy && !dirty && !pending,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _requestClose(source: 'system_back');
      },
      child: CommonSideDockFrame(
        title: headerPlateNumber,
        subtitle: '차량 정보 수정',
        icon: Icons.directions_car_filled_rounded,
        closeEnabled: !busy,
        onClose: () => _requestClose(source: 'header_close'),
        onHeaderTap: null,
        headerAction: AnimatedSwitcher(
          duration: MediaQuery.maybeOf(context)?.disableAnimations == true
              ? Duration.zero
              : const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: .92, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: widget.trace?.developerMode == true
              ? CommonIconButton(
                  key: const ValueKey<String>('modify_debug_action'),
                  icon: Icons.bug_report_rounded,
                  tooltip: '디버그 상태',
                  size: 38,
                  iconSize: 19,
                  haptic: CommonHaptic.selection,
                  onPressed: _showDeveloperStatus,
                )
              : const SizedBox.shrink(
                  key: ValueKey<String>('modify_debug_action_hidden'),
                ),
        ),
        leadingRail: PlateEditorRail(
          enabled: !busy,
          policy: policy,
          disabledWorkspaces: _disabledMonthlyWorkspaces,
          selectedWorkspace: _activeDialog,
          onSelected: (workspace) => _openEditorDialog(
            workspace,
            policy,
            source: 'rail',
          ),
        ),
        collapseLeadingRail: false,
        footer: PlateEditorFooter(
          message: footerMessage,
          actionLabel: '수정 완료',
          actionIcon: pending
              ? Icons.pending_actions_rounded
              : Icons.save_rounded,
          loading: isLoading,
          warning: pending,
          emphasized: !pending && dirty,
          onPressed: busy || pending || !dirty ? null : _handleModifyAction,
        ),
        child: KeyedSubtree(
          key: const ValueKey<String>('modify_overview'),
          child: _buildOverview(policy),
        ),
      ),
    );
  }
}
