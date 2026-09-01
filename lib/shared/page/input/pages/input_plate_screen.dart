import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/location/applications/location_state.dart';
import '../../../../features/payment/applications/bill_state.dart';
import '../../../../features/payment/domain/models/bill_model.dart';
import '../../../../features/sector/applications/sector_state.dart';
import '../../../../features/sector/domain/models/sector_model.dart';
import '../../../operational_cache/domain/repositories/operational_local_repository.dart';
import '../../../plate/domain/models/plate_status_lookup_result.dart';
import '../../../plate/domain/models/plate_status_scope.dart';
import '../../../plate/domain/repositories/plate_repository.dart';
import '../../../plate/domain/services/plate_status_record.dart';
import '../../../plate/editor/domain/plate_editor_workspace.dart';
import '../../../plate/editor/domain/plate_identity_focus_target.dart';
import '../../../plate/editor/domain/plate_parking_display.dart';
import '../../../plate/editor/widgets/plate_editor_footer.dart';
import '../../../plate/editor/widgets/plate_editor_overview.dart';
import '../../../plate/editor/widgets/plate_editor_rail.dart';
import '../../../plate/editor/workspaces/plate_billing_workspace.dart';
import '../../../plate/editor/workspaces/plate_camera_workspace.dart';
import '../../../plate/editor/workspaces/plate_memo_workspace.dart';
import '../../../plate/editor/widgets/plate_parking_picker_content.dart';
import '../../../plate/editor/workspaces/plate_sector_workspace.dart';
import '../../../plate/editor/dialogs/plate_editor_dialog.dart';
import '../../../plate/editor/workspaces/plate_identity_workspace.dart';
import '../application/input_plate_registration_policy.dart';
import '../controllers/input_plate_controller.dart';
import 'live_ocr_page.dart';
import '../widgets/live_ocr_source_rect_route.dart';
import 'sheets/input_region_bottom_sheet.dart';

enum _MonthlyFetchFailureType { notFound, inactive, readError }

class _MonthlyFetchResult {
  const _MonthlyFetchResult.success({
    required this.data,
    required this.sourcePath,
  })  : failure = null,
        error = null;

  const _MonthlyFetchResult.failure(
      this.failure, {
        this.error,
      })  : data = null,
        sourcePath = null;

  final PlateStatusRecord? data;
  final String? sourcePath;
  final _MonthlyFetchFailureType? failure;
  final Object? error;

  bool get isSuccess => data != null && sourcePath != null;
}

class InputPlateScreen extends StatefulWidget {
  const InputPlateScreen({
    super.key,
    this.isMinorMode = false,
    this.initialOcrSourceRect,
    this.sideDockPresentationController,
  });

  final bool isMinorMode;
  final Rect? initialOcrSourceRect;
  final CommonSideDockPresentationController? sideDockPresentationController;

  @override
  State<InputPlateScreen> createState() => _InputPlateScreenState();
}

class _InputPlateScreenState extends State<InputPlateScreen> {

  late final InputPlateController controller;
  final TextEditingController _identityFrontDraftController =
  TextEditingController();
  final TextEditingController _identityMidDraftController =
  TextEditingController();
  final TextEditingController _identityBackDraftController =
  TextEditingController();
  final TextEditingController _memoDraftController = TextEditingController();
  final GlobalKey _overviewPlateAnchorKey = GlobalKey();
  final GlobalKey _identityPlateAnchorKey = GlobalKey();

  PlateRepository get _plateRepo => context.read<PlateRepository>();

  PlateEditorWorkspace? _activeDialog;
  String _policySignature = '';
  bool _identityPending = false;
  bool _identityEditing = false;
  bool _identityAutoApplying = false;
  bool _syncingIdentityDraft = false;
  PlateIdentityFocusTarget _identityInitialFocus =
      PlateIdentityFocusTarget.front;
  List<String> _identityMiddleSuggestions = const <String>[];
  bool _memoPending = false;
  bool _hasMonthlyParking = false;
  bool _hasMonthlyLoaded = false;
  int _statusLookupGeneration = 0;
  int _monthlyLookupGeneration = 0;
  String? _historyStatusCacheKey;
  PlateStatusLookupResult? _historyStatusCacheResult;
  bool _openedScannerOnce = false;
  bool _scannerActive = false;
  DeveloperOperationTrace? _editorTrace;
  int _cameraSessionKey = 0;
  bool _cameraStartInPreview = false;
  List<dynamic> _cameraInitialPreviewImages = const <dynamic>[];
  int _cameraInitialPreviewIndex = 0;

  bool get _busy => controller.isLoading;

  bool _isBillingWorkspace(PlateEditorWorkspace workspace) {
    return workspace == PlateEditorWorkspace.variableBilling ||
        workspace == PlateEditorWorkspace.regularBilling;
  }

  bool _isMonthlyLockedWorkspace(PlateEditorWorkspace workspace) {
    return _isBillingWorkspace(workspace) ||
        workspace == PlateEditorWorkspace.memo;
  }

  Set<PlateEditorWorkspace> get _disabledMonthlyWorkspaces =>
      controller.monthlyBillingLocked
          ? const <PlateEditorWorkspace>{
        PlateEditorWorkspace.variableBilling,
        PlateEditorWorkspace.regularBilling,
        PlateEditorWorkspace.memo,
      }
          : const <PlateEditorWorkspace>{};

  bool get _hasPendingWorkspaceDraft => _memoPending;

  bool get _hasEnteredContent {
    return controller.controllerFrontDigit.text.trim().isNotEmpty ||
        controller.controllerMidDigit.text.trim().isNotEmpty ||
        controller.controllerBackDigit.text.trim().isNotEmpty ||
        controller.locationController.text.trim().isNotEmpty ||
        controller.capturedImages.isNotEmpty ||
        controller.customStatusController.text.trim().isNotEmpty ||
        (controller.selectedBill?.trim().isNotEmpty ?? false) ||
        (controller.selectedSectorId?.trim().isNotEmpty ?? false) ||
        _hasPendingWorkspaceDraft;
  }

  @override
  void initState() {
    super.initState();
    controller = InputPlateController(isMinorMode: widget.isMinorMode);
    if (controller.selectedBillType.trim().isEmpty) {
      controller.selectedBillType = '변동';
    }
    _syncIdentityDraftFromCommitted();
    _memoDraftController.text = controller.customStatusController.text;
    _identityFrontDraftController.addListener(_handleIdentityDraftChanged);
    _identityMidDraftController.addListener(_handleIdentityDraftChanged);
    _identityBackDraftController.addListener(_handleIdentityDraftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeEditor());
  }

  Future<void> _initializeEditor() async {
    if (!mounted) return;
    final areaState = context.read<AreaState>();
    final policy = PlateEditorPolicy.fromCapabilities(
      area: areaState.currentArea,
      capabilities: areaState.capabilitiesOfCurrentArea,
    );
    _policySignature = policy.signature;
    _editorTrace = await DeveloperOperationTrace.start(
      context: context,
      title: '차량 등록',
      initialMessage: '차량 등록 Side Dock을 준비합니다.',
      useCommonUi: true,
      developerModeMessage:
      '개발자 모드 ON: 등록 흐름의 debugPrint 코드를 Status Dialog에서 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 등록 흐름을 콘솔에 기록합니다.',
      showDialogImmediately: false,
    );
    if (!mounted) return;
    setState(() {});
    _log(
      'input_editor=open area=${policy.area} bill=${policy.hasBill} sector=${policy.hasSector}',
      progress: .08,
    );
    _log('overview=ready display=list_surface editMode=central', progress: .12);
    _log(
      'regular_billing_ui=read_only rail=hidden contentLabel=정기 등록 railVariableLabel=정산',
      progress: .125,
    );
    _log(
      'content_status_labels required=필수 입력 optional=선택 입력 complete=입력 완료 minorParkingOptional=${widget.isMinorMode}',
      progress: .13,
    );
    final monthlyFlagFuture = _loadHasMonthlyParkingFlag();
    final billState = context.read<BillState>();
    final sectorState = context.read<SectorState>();
    final preload = Stopwatch()..start();
    final preloadTasks = <Future<void>>[
      if (policy.hasBill) billState.loadFromBillCache(),
      if (policy.hasSector) sectorState.waitUntilReady(),
    ];
    final preloadFuture = (preloadTasks.isEmpty
        ? Future<void>.value()
        : Future.wait<void>(preloadTasks).then<void>((_) {}))
        .whenComplete(preload.stop);
    await _openInitialScannerFirst();
    if (!mounted) return;
    await monthlyFlagFuture;
    await preloadFuture;
    _log(
      'preload=complete elapsedMs=${preload.elapsedMilliseconds} billEnabled=${policy.hasBill} billGeneral=${billState.generalBills.length} billRegular=${billState.regularBills.length} sectorEnabled=${policy.hasSector} sectorCount=${sectorState.sectors.length}',
      progress: .18,
    );
    if (!mounted) return;
    setState(() {
      controller.isLocationSelected =
          controller.locationController.text.trim().isNotEmpty;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadHasMonthlyParkingFlag();
  }

  @override
  void dispose() {
    _identityFrontDraftController.removeListener(_handleIdentityDraftChanged);
    _identityMidDraftController.removeListener(_handleIdentityDraftChanged);
    _identityBackDraftController.removeListener(_handleIdentityDraftChanged);
    _identityFrontDraftController.dispose();
    _identityMidDraftController.dispose();
    _identityBackDraftController.dispose();
    _memoDraftController.dispose();
    controller.dispose();
    super.dispose();
  }

  void _log(String message, {double? progress}) {
    final trace = _editorTrace;
    if (trace != null) {
      trace.log(message, progress: progress);
      return;
    }
    debugPrint('[InputPlateEditor] $message');
  }

  String _safeArea(String area) {
    final value = area.trim();
    return value.isEmpty ? 'unknown' : value;
  }

  String _historyStatusKey(String plateNumber, String area) {
    return '${_safeArea(area)}|${plateNumber.trim()}';
  }

  void _clearHistoryStatusCache() {
    _historyStatusCacheKey = null;
    _historyStatusCacheResult = null;
  }

  void _showFloatingMessage(String message) {
    if (!mounted) return;
    showSelectedSnackbar(context, message, useCommonUi: true);
  }

  String _rectDebug(Rect rect) {
    return '${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)},${rect.width.toStringAsFixed(1)},${rect.height.toStringAsFixed(1)}';
  }

  Rect _fallbackOcrSourceRect() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: 44,
      height: 44,
    );
  }

  Rect? _globalRectForKey(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) return null;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    final rect = origin & renderObject.size;
    if (rect.isEmpty || !rect.isFinite) return null;
    return rect;
  }

  Future<Rect?> _waitForTargetRect(GlobalKey key) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted) return null;
      await WidgetsBinding.instance.endOfFrame;
      final rect = _globalRectForKey(key);
      if (rect != null) return rect;
      await Future<void>.delayed(Duration.zero);
    }
    return null;
  }

  Future<void> _waitForSideDockSettled() async {
    if (!mounted) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      await WidgetsBinding.instance.endOfFrame;
      return;
    }
    if (animation.status == AnimationStatus.dismissed ||
        animation.status == AnimationStatus.reverse) {
      return;
    }
    final completer = Completer<void>();
    late AnimationStatusListener listener;
    listener = (status) {
      if (completer.isCompleted) return;
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed ||
          status == AnimationStatus.reverse) {
        completer.complete();
      }
    };
    animation.addStatusListener(listener);
    listener(animation.status);
    try {
      await completer.future;
      if (mounted) await WidgetsBinding.instance.endOfFrame;
    } finally {
      animation.removeStatusListener(listener);
    }
  }

  Future<void> _handleLiveOcrFollowup(
      PlateIdentityAuxiliaryResult result, {
        required String source,
        bool allowScannerActive = false,
      }) async {
    if (!mounted) return;
    if (!result.requiresManualCompletion) {
      _log(
        'ocr=followup_identity_skipped reason=identity_complete applied=${result.applied} focus=${result.focusTarget.name} source=$source',
        progress: .34,
      );
      return;
    }
    _log(
      'ocr=followup_identity_wait reason=manual_completion applied=${result.applied} focus=${result.focusTarget.name} suggestions=${result.middleSuggestions.join('|')} source=$source',
      progress: .31,
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (_activeDialog != null || _identityEditing) {
      _log(
        'ocr=followup_identity_skipped reason=editor_active dialog=${_activeDialog?.name ?? 'none'} identityEditing=$_identityEditing source=$source',
      );
      return;
    }
    _log(
      'ocr=followup_identity_open reason=manual_completion focus=${result.focusTarget.name} applied=${result.applied} suggestions=${result.middleSuggestions.join('|')} source=$source',
      progress: .34,
    );
    _enterIdentityEditor(
      source: '${source}_manual_completion',
      initialFocus: result.focusTarget,
      middleSuggestions: result.middleSuggestions,
      allowScannerActive: allowScannerActive,
    );
  }

  Future<void> _openInitialScannerFirst() async {
    if (!mounted || _openedScannerOnce || _scannerActive) return;
    final sourceRect = widget.initialOcrSourceRect;
    if (sourceRect == null || sourceRect.isEmpty || !sourceRect.isFinite) {
      widget.sideDockPresentationController?.show();
      _log('ocr=auto_skipped reason=missing_entry_source');
      return;
    }
    _log(
      'ocr=transition_open source=status_entry rect=${_rectDebug(sourceRect)}',
      progress: .20,
    );
    PlateIdentityAuxiliaryResult? result;
    try {
      result = await _openLiveScanner(
        automatic: true,
        source: 'status_entry',
        sourceRect: sourceRect,
      );
    } finally {
      if (mounted) widget.sideDockPresentationController?.show();
    }
    if (!mounted) return;
    if (result == null) {
      _log('ocr=auto_closed result=none source=status_entry');
      return;
    }
    _log(
      'ocr=auto_closed applied=${result.applied} manualCompletion=${result.requiresManualCompletion} focus=${result.focusTarget.name}',
      progress: .36,
    );
  }

  Future<void> _openScannerFromRail(Rect sourceRect) async {
    if (!mounted || _busy || _scannerActive) {
      _log(
        'ocr=rail_open_skipped busy=$_busy scannerActive=$_scannerActive',
      );
      return;
    }
    _log('ocr=transition_open source=rail_ocr rect=${_rectDebug(sourceRect)}');
    final result = await _openLiveScanner(
      source: 'rail_action',
      sourceRect: sourceRect,
    );
    if (!mounted || result == null) return;
    _log(
      'ocr=rail_result applied=${result.applied} manualCompletion=${result.requiresManualCompletion} focus=${result.focusTarget.name}',
    );
  }

  Future<void> _loadHasMonthlyParkingFlag() async {
    try {
      final area = context.read<AreaState>().currentArea.trim();
      final meta = area.isEmpty
          ? null
          : await context.read<OperationalLocalRepository>().readAreaMeta(area);
      final value = meta?.hasMonthlyParking ?? false;
      if (!mounted) return;
      if (!_hasMonthlyLoaded || _hasMonthlyParking != value) {
        setState(() {
          _hasMonthlyParking = value;
          _hasMonthlyLoaded = true;
        });
      }
    } catch (error) {
      _log('monthly_flag=load_failed error=$error');
      if (!mounted) return;
      if (!_hasMonthlyLoaded) {
        setState(() {
          _hasMonthlyParking = false;
          _hasMonthlyLoaded = true;
        });
      }
    }
  }

  void _syncIdentityDraftFromCommitted() {
    _syncingIdentityDraft = true;
    _identityFrontDraftController.text = controller.controllerFrontDigit.text;
    _identityMidDraftController.text = controller.controllerMidDigit.text;
    _identityBackDraftController.text = controller.controllerBackDigit.text;
    _identityPending = false;
    _syncingIdentityDraft = false;
  }

  void _handleIdentityDraftChanged() {
    if (!mounted || _syncingIdentityDraft) return;
    final pending = _identityFrontDraftController.text !=
        controller.controllerFrontDigit.text ||
        _identityMidDraftController.text != controller.controllerMidDigit.text ||
        _identityBackDraftController.text != controller.controllerBackDigit.text;
    if (_identityPending == pending) {
      setState(() {});
      return;
    }
    setState(() => _identityPending = pending);
    _log(
      'identity=draft_changed pending=$pending frontLength=${_identityFrontDraftController.text.trim().length} middleLength=${_identityMidDraftController.text.trim().length} backLength=${_identityBackDraftController.text.trim().length}',
    );
  }

  Future<void> _openRegionPicker({String source = 'overview_region'}) async {
    if (!mounted || _busy || _activeDialog != null || _identityEditing || _scannerActive) {
      _log(
        'identity_region=open_skipped source=$source busy=$_busy dialog=${_activeDialog?.name ?? 'none'} editing=$_identityEditing scanner=$_scannerActive',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    _log(
      'identity_region=picker_open source=$source current=${controller.dropdownValue}',
    );
    await inputRegionPickerBottomSheet(
      context: context,
      selectedRegion: controller.dropdownValue,
      regions: controller.regions,
      useCommonUi: true,
      onConfirm: (selected) {
        if (!mounted) return;
        final next = selected.trim();
        if (next.isEmpty) return;
        final previous = controller.dropdownValue;
        if (previous == next) {
          _log(
            'identity_region=unchanged source=$source region=$next',
          );
          return;
        }
        setState(() => controller.dropdownValue = next);
        HapticFeedback.selectionClick();
        _log(
          'identity_region=applied source=$source previous=$previous current=$next plate=${controller.buildPlateNumber()}',
        );
      },
    );
  }

  void _syncControllerIdentityFocus(PlateIdentityFocusTarget target) {
    switch (target) {
      case PlateIdentityFocusTarget.front:
        controller.setActiveController(controller.controllerFrontDigit);
        break;
      case PlateIdentityFocusTarget.middle:
        controller.setActiveController(controller.controllerMidDigit);
        break;
      case PlateIdentityFocusTarget.back:
        controller.setActiveController(controller.controllerBackDigit);
        break;
    }
    _log('identity_focus=${target.name}');
  }

  PlateIdentityFocusTarget _resolveIdentityFocus({
    PlateIdentityFocusTarget fallback = PlateIdentityFocusTarget.front,
  }) {
    return resolvePlateIdentityFocusTarget(
      front: controller.controllerFrontDigit.text,
      middle: controller.controllerMidDigit.text,
      back: controller.controllerBackDigit.text,
      requiredFrontLength: controller.isThreeDigit ? 3 : 2,
      fallback: fallback,
    );
  }

  bool get _identityDraftValid {
    final front = _identityFrontDraftController.text.trim();
    final middle = _identityMidDraftController.text.trim();
    final back = _identityBackDraftController.text.trim();
    return RegExp(r'^\d{2,3}$').hasMatch(front) &&
        RegExp(r'^[가-힣]$').hasMatch(middle) &&
        RegExp(r'^\d{4}$').hasMatch(back);
  }

  Future<void> _applyIdentityDraft() async {
    if (_identityAutoApplying || !_identityEditing || !_identityDraftValid) {
      _log(
        'identity=auto_apply_skipped editing=$_identityEditing applying=$_identityAutoApplying valid=$_identityDraftValid',
      );
      return;
    }
    _identityAutoApplying = true;
    final front = _identityFrontDraftController.text.trim();
    final mid = _identityMidDraftController.text.trim();
    final back = _identityBackDraftController.text.trim();
    controller.suppressOcrEditCount(true);
    setState(() {
      controller.isThreeDigit = front.length == 3;
      controller.controllerFrontDigit.text = front;
      controller.controllerMidDigit.text = mid;
      controller.controllerBackDigit.text = back;
      _identityPending = false;
      _identityEditing = false;
      _identityMiddleSuggestions = const <String>[];
      _monthlyLookupGeneration++;
      controller.unlockMonthlyBilling(clearSelection: true);
      controller.resetStatusLookupToIdle();
      _clearHistoryStatusCache();
    });
    controller.suppressOcrEditCount(false);
    _identityAutoApplying = false;
    _log(
      'identity=auto_applied region=${controller.dropdownValue} plate=${controller.buildPlateNumber()}',
    );
    _log('identity_editor=closed reason=auto_apply');
    _log('identity_editor=exclusive_mode rail=restored overview=restored footer=restored');
    unawaited(_lookupGeneralStatusForCurrentPlate());
  }

  void _enterIdentityEditor({
    required String source,
    PlateIdentityFocusTarget? initialFocus,
    List<String> middleSuggestions = const <String>[],
    bool allowScannerActive = false,
  }) {
    if (!mounted ||
        _busy ||
        _activeDialog != null ||
        (_scannerActive && !allowScannerActive)) {
      _log(
        'identity_editor=open_skipped source=$source busy=$_busy dialog=${_activeDialog?.name ?? 'none'} scanner=$_scannerActive',
      );
      return;
    }
    if (!_identityPending) _syncIdentityDraftFromCommitted();
    final focus = initialFocus ??
        resolvePlateIdentityFocusTarget(
          front: _identityFrontDraftController.text,
          middle: _identityMidDraftController.text,
          back: _identityBackDraftController.text,
          requiredFrontLength:
          _identityFrontDraftController.text.trim().length == 2 ? 2 : 3,
        );
    setState(() {
      _identityEditing = true;
      _identityAutoApplying = false;
      _identityInitialFocus = focus;
      _identityMiddleSuggestions = List<String>.from(
        middleSuggestions,
        growable: false,
      );
    });
    _syncControllerIdentityFocus(focus);
    _log('identity_editor=exclusive_mode rail=collapsed overview=hidden footer=hidden');
    _log(
      'identity_editor=open source=$source focus=${focus.name} suggestions=${middleSuggestions.join('|')}',
    );
  }

  void _exitIdentityEditor({required String reason}) {
    if (!_identityEditing || _identityAutoApplying) return;
    _syncIdentityDraftFromCommitted();
    setState(() {
      _identityEditing = false;
      _identityMiddleSuggestions = const <String>[];
    });
    HapticFeedback.selectionClick();
    _log('identity_editor=closed reason=$reason action=discard');
    _log('identity_editor=exclusive_mode rail=restored overview=restored footer=restored');
  }

  void _syncMemoDraftFromCommitted() {
    if (_memoPending) return;
    _memoDraftController.text = controller.customStatusController.text;
  }

  PlateEditorDialogSize _dialogSize(PlateEditorWorkspace workspace) {
    switch (workspace) {
      case PlateEditorWorkspace.parking:
        return PlateEditorDialogSize.wide;
      case PlateEditorWorkspace.camera:
        return PlateEditorDialogSize.immersive;
      case PlateEditorWorkspace.vehicleIdentity:
        return PlateEditorDialogSize.standard;
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
        return '차량 등록 정보';
    }
  }

  Future<void> _openEditorDialog(
      PlateEditorWorkspace workspace,
      PlateEditorPolicy policy, {
        required String source,
        List<dynamic> previewImages = const <dynamic>[],
        int previewIndex = 0,
      }) async {
    if (_busy || _activeDialog != null || _identityEditing) return;
    if (workspace == PlateEditorWorkspace.overview || !policy.supports(workspace)) {
      return;
    }
    if (controller.monthlyBillingLocked &&
        _isMonthlyLockedWorkspace(workspace)) {
      _log(
        'workspace=blocked reason=monthly_parking workspace=${workspace.name} source=$source',
      );
      return;
    }
    if (workspace == PlateEditorWorkspace.vehicleIdentity) {
      _enterIdentityEditor(source: source);
      return;
    }
    if (workspace == PlateEditorWorkspace.regularBilling) {
      _log(
        'workspace=ignored reason=regular_billing_read_only source=$source',
      );
      return;
    }
    if (workspace == PlateEditorWorkspace.variableBilling &&
        controller.selectedBillType != '변동') {
      await _changeBillType('변동');
      if (!mounted) return;
    }
    if (workspace == PlateEditorWorkspace.memo && !_memoPending) {
      _syncMemoDraftFromCommitted();
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

  void _syncPolicy(PlateEditorPolicy policy) {
    if (_policySignature == policy.signature) return;
    final previous = _policySignature;
    _policySignature = policy.signature;
    if (!policy.hasSector) controller.clearSelectedSector();
    _log('capabilities=changed previous=$previous current=${policy.signature}');
    final active = _activeDialog;
    if (active != null && !policy.supports(active)) {
      _log('dialog=${active.name}_capability_invalidated');
    }
  }

  void _applyParking(String location) {
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
      controller.locationController.text = normalized;
      controller.isLocationSelected = normalized.isNotEmpty;
    });
    _log('parking_location=auto_applied location=$normalized');
    _log(
      'parking_display=resolved tower=$isTower internal=$normalized visible=$displayLocation towerSlotVisibility=${isTower ? 'hidden' : 'visible'}',
    );
    _log('registration_action=state label=입차 완료 parking=true');
  }

  void _clearParkingLocation() {
    final previous = controller.locationController.text.trim();
    final previousPriorities = controller.selectedParkingPriorities.join('|');
    setState(() {
      controller.clearParkingSelection();
    });
    HapticFeedback.selectionClick();
    _log(
      'parking=cleared previousLocation=$previous previousPriorities=$previousPriorities',
    );
    _log('registration_action=state label=입차 요청 parking=false');
  }

  void _clearSectorSelection() {
    final previousId = controller.selectedSectorId?.trim() ?? '';
    final previousName = controller.selectedSectorName?.trim() ?? '';
    setState(controller.clearSelectedSector);
    HapticFeedback.selectionClick();
    _log(
      'sector=cleared previousSectorId=$previousId previousSectorName=$previousName',
    );
  }

  Future<void> _clearBillingSelection(String type) async {
    if (controller.monthlyBillingLocked) {
      _log('billing=clear_blocked reason=monthly_parking targetType=$type');
      return;
    }
    final previousType = controller.selectedBillType;
    final previousValue = controller.selectedBill?.trim().isNotEmpty == true
        ? controller.selectedBill!.trim()
        : controller.countTypeController.text.trim();
    setState(() {
      controller.clearBillingSelection(resetType: false);
      controller.selectedBillType = type;
      _statusLookupGeneration++;
      _monthlyLookupGeneration++;
      controller.resetStatusLookupToIdle();
    });
    HapticFeedback.selectionClick();
    _log(
      'billing=cleared targetType=$type previousType=$previousType previousValue=$previousValue',
    );
  }

  Future<void> _applySector(SectorModel sector) async {
    controller.setSelectedSector(sector);
    if (!mounted) return;
    setState(() {});
    HapticFeedback.selectionClick();
    _log('sector=selected id=${sector.id} name=${sector.name}');
  }

  void _applyMemo(String value) {
    if (controller.monthlyBillingLocked) {
      _log('memo=blocked reason=monthly_parking action=apply');
      return;
    }
    setState(() {
      controller.customStatusController.text = value;
      controller.markStatusDraftEdited();
      _memoPending = false;
    });
    HapticFeedback.selectionClick();
    _log('memo=applied length=${value.trim().length}');
  }

  Future<PlateStatusLookupResult> _fetchPlateStatus(
      String plateNumber,
      String area,
      ) {
    return _plateRepo.lookupPlateStatus(
      plateNumber: plateNumber,
      area: _safeArea(area),
      scope: PlateStatusScope.history,
    );
  }

  Future<_MonthlyFetchResult> _fetchMonthlyPlateStatus(
      String plateNumber,
      String area,
      ) async {
    final result = await _plateRepo.lookupPlateStatus(
      plateNumber: plateNumber,
      area: _safeArea(area),
      scope: PlateStatusScope.monthly,
    );
    if (result.isFound) {
      return _MonthlyFetchResult.success(
        data: result.record,
        sourcePath: result.sourcePath,
      );
    }
    if (result.isInactive) {
      return const _MonthlyFetchResult.failure(
        _MonthlyFetchFailureType.inactive,
      );
    }
    if (result.isNotFound) {
      return const _MonthlyFetchResult.failure(
        _MonthlyFetchFailureType.notFound,
      );
    }
    return _MonthlyFetchResult.failure(
      _MonthlyFetchFailureType.readError,
      error: result.error,
    );
  }

  Future<void> _lookupGeneralStatusForCurrentPlate({
    bool preserveBillingType = false,
    bool forceRefresh = false,
  }) async {
    if (!controller.isInputValid()) {
      final generation = ++_statusLookupGeneration;
      if (!mounted) return;
      setState(() {
        controller.resetStatusLookupToIdle();
        _monthlyLookupGeneration++;
      });
      _log('status_lookup=reset generation=$generation reason=incomplete_plate');
      return;
    }

    final plateNumber = controller.buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final cacheKey = _historyStatusKey(plateNumber, area);
    final cachedLookup = !forceRefresh && _historyStatusCacheKey == cacheKey
        ? _historyStatusCacheResult
        : null;
    final lookupGeneration = ++_statusLookupGeneration;
    setState(() {
      controller.beginStatusLookup();
      _monthlyLookupGeneration++;
    });
    _log(
      'status_lookup=start plate=$plateNumber area=$area generation=$lookupGeneration source=${cachedLookup == null ? 'firestore' : 'side_dock_cache'} forceRefresh=$forceRefresh',
    );

    final lookup = cachedLookup ?? await _fetchPlateStatus(plateNumber, area);
    if (!mounted || lookupGeneration != _statusLookupGeneration) return;
    if (!controller.isInputValid() || controller.buildPlateNumber() != plateNumber) {
      return;
    }
    if (cachedLookup == null) {
      _historyStatusCacheKey = cacheKey;
      _historyStatusCacheResult = lookup;
    }

    if (lookup.isFailed) {
      setState(controller.applyStatusLookupFailed);
      _log('status_lookup=failed plate=$plateNumber area=$area error=${lookup.error}');
      _showFloatingMessage('기존 상태 정보를 확인하지 못했습니다. 저장 시 기존 상태를 보호합니다.');
      return;
    }
    if (lookup.isInactive) {
      setState(controller.applyStatusInactive);
      _log('status_lookup=inactive plate=$plateNumber area=$area');
      _showFloatingMessage('상태 정보의 유효기간을 확인할 수 없습니다.');
      return;
    }
    if (lookup.isNotFound) {
      setState(controller.applyStatusNotFound);
      _syncMemoDraftFromCommitted();
      _log('status_lookup=not_found plate=$plateNumber area=$area');
      if (controller.selectedBillType == '정기') {
        await _handleMonthlySelectedFetchAndApply();
      }
      return;
    }

    final data = lookup.record!;
    final isMonthlyParkingMarker = data.type?.trim() == '정기 주차';
    if (isMonthlyParkingMarker) {
      setState(() {
        controller.selectedBillType = '정기';
        controller.selectedBill = null;
        controller.countTypeController.clear();
      });
      _log(
        'status_lookup=monthly_marker plate=$plateNumber area=$area sourcePath=${lookup.sourcePath ?? ''}',
        progress: .46,
      );
      await _handleMonthlySelectedFetchAndApply(
        recognizedFromPlateStatus: true,
      );
      return;
    }

    final fetchedStatus = data.customStatus;
    final fetchedCountType = data.countType;
    final shouldResolveMonthly = !preserveBillingType &&
        (controller.selectedBillType == '정기' ||
            (fetchedCountType != null && fetchedCountType.isNotEmpty));
    setState(() {
      controller.applyFetchedStatus(
        customStatus: fetchedStatus,
        sourcePath: lookup.sourcePath!,
      );
      if (!preserveBillingType &&
          fetchedCountType != null &&
          fetchedCountType.isNotEmpty) {
        controller.countTypeController.text = fetchedCountType;
        controller.selectedBillType = '정기';
        controller.selectedBill = fetchedCountType;
      }
    });
    _syncMemoDraftFromCommitted();
    _log(
      'status_lookup=found plate=$plateNumber area=$area memoLength=${(fetchedStatus ?? '').trim().length} countType=${fetchedCountType ?? ''}',
    );
    if (shouldResolveMonthly) {
      await _handleMonthlySelectedFetchAndApply();
    }
  }

  Future<void> _handleMonthlySelectedFetchAndApply({
    bool recognizedFromPlateStatus = false,
  }) async {
    if (!controller.isInputValid()) {
      if (!mounted) return;
      setState(() {
        _monthlyLookupGeneration++;
      });
      await StatusDialog.showFailure(
        context,
        title: StatusDialog.invalidPlateInput,
        useCommonUi: true,
      );
      return;
    }

    final plateNumber = controller.buildPlateNumber();
    final area = _safeArea(context.read<AreaState>().currentArea);
    final lookupGeneration = ++_monthlyLookupGeneration;
    setState(() {
      controller.beginStatusLookup();
    });
    _log(
      'monthly_lookup=start plate=$plateNumber area=$area generation=$lookupGeneration',
    );

    try {
      final result = await _fetchMonthlyPlateStatus(plateNumber, area);
      if (!mounted) return;
      final currentPlate =
      controller.isInputValid() ? controller.buildPlateNumber() : '';
      final currentArea = _safeArea(context.read<AreaState>().currentArea);
      final stale = lookupGeneration != _monthlyLookupGeneration ||
          currentPlate != plateNumber ||
          currentArea != area ||
          controller.selectedBillType != '정기';
      if (stale) {
        _log(
          'monthly_lookup=discarded requestedPlate=$plateNumber currentPlate=$currentPlate requestedArea=$area currentArea=$currentArea requestedGeneration=$lookupGeneration currentGeneration=$_monthlyLookupGeneration',
        );
        return;
      }
      if (!result.isSuccess) {
        setState(() {
          if (result.failure == _MonthlyFetchFailureType.readError) {
            controller.applyStatusLookupFailed();
          } else if (result.failure == _MonthlyFetchFailureType.inactive) {
            controller.applyStatusInactive();
          } else {
            controller.applyStatusNotFound();
          }
        });
        _syncMemoDraftFromCommitted();
        _log(
          'monthly_lookup=failed type=${result.failure?.name ?? 'unknown'} error=${result.error ?? ''} recognizedFromPlateStatus=$recognizedFromPlateStatus',
        );
        if (recognizedFromPlateStatus) {
          setState(() {
            controller.unlockMonthlyBilling(clearSelection: true);
          });
        }
        if (result.failure == _MonthlyFetchFailureType.inactive) {
          await StatusDialog.showFailure(
            context,
            title: '정기 주차 기간이 만료되었습니다.',
            useCommonUi: true,
          );
        } else if (result.failure == _MonthlyFetchFailureType.notFound) {
          await StatusDialog.showFailure(
            context,
            title: StatusDialog.monthlyDocNotFound,
            useCommonUi: true,
          );
        } else {
          _showFloatingMessage('정기 주차 정보를 불러오지 못했습니다.');
        }
        return;
      }

      final data = result.data!;
      final fetchedStatus = data.customStatus;
      final fetchedCountType = data.countType;
      final sourcePath = result.sourcePath!;
      if (recognizedFromPlateStatus &&
          (fetchedCountType == null || fetchedCountType.trim().isEmpty)) {
        setState(() {
          controller.unlockMonthlyBilling(clearSelection: true);
          controller.applyStatusNotFound();
        });
        _syncMemoDraftFromCommitted();
        _log(
          'monthly_lookup=invalid_marker_source reason=count_type_empty sourcePath=$sourcePath',
        );
        await StatusDialog.showFailure(
          context,
          title: StatusDialog.monthlyApplyFailed,
          useCommonUi: true,
        );
        return;
      }
      setState(() {
        controller.applyFetchedStatus(
          customStatus: recognizedFromPlateStatus ? null : fetchedStatus,
          sourcePath: sourcePath,
        );
        if (fetchedCountType != null && fetchedCountType.isNotEmpty) {
          controller.countTypeController.text = fetchedCountType;
          controller.selectedBill = fetchedCountType;
        }
        if (recognizedFromPlateStatus &&
            fetchedCountType != null &&
            fetchedCountType.isNotEmpty) {
          controller.lockMonthlyBilling(fetchedCountType);
        }
      });
      _syncMemoDraftFromCommitted();
      _log(
        'monthly_lookup=found sourcePath=$sourcePath memoLength=${(fetchedStatus ?? '').trim().length} countType=${fetchedCountType ?? ''} recognizedFromPlateStatus=$recognizedFromPlateStatus locked=${controller.monthlyBillingLocked}',
        progress: .58,
      );
      if (recognizedFromPlateStatus && controller.monthlyBillingLocked) {
        await HapticFeedback.mediumImpact();
        await _showMonthlyParkingRecognitionDialog(data);
      }
    } catch (error, stackTrace) {
      _log('monthly_lookup=exception error=$error stack=$stackTrace');
      if (mounted && recognizedFromPlateStatus) {
        setState(() {
          controller.unlockMonthlyBilling(clearSelection: true);
        });
      }
      if (mounted) _showFloatingMessage('정기 주차 정보를 불러오지 못했습니다.');
    }
  }

  Future<void> _showMonthlyParkingRecognitionDialog(
      PlateStatusRecord record,
      ) async {
    if (!mounted) return;
    final rows = <String>[
      '차량번호 ${controller.buildPlateNumber()}',
      if ((record.countType ?? '').trim().isNotEmpty)
        '정기 정산 ${(record.countType ?? '').trim()}',
      if ((record.regularType ?? '').trim().isNotEmpty)
        '상품 ${(record.regularType ?? '').trim()}',
      if ((record.startDate ?? '').trim().isNotEmpty ||
          (record.endDate ?? '').trim().isNotEmpty)
        '기간 ${(record.startDate ?? '').trim()} ~ ${(record.endDate ?? '').trim()}',
      if ((record.regularAmount ?? 0) > 0)
        '요금 ${record.regularAmount}원',
      if ((record.customStatus ?? '').trim().isNotEmpty)
        '상태 메모 ${(record.customStatus ?? '').trim()}',
      if ((record.specialNote ?? '').trim().isNotEmpty)
        '특이사항 ${(record.specialNote ?? '').trim()}',
    ];
    final trace = _editorTrace;
    final debugCode = trace?.developerMode == true
        ? trace!.debugPrintCode
        : null;
    await StatusDialog.showSuccess(
      context,
      title: '월 주차 차량',
      description: rows.join('\n'),
      copyText: debugCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  Future<void> _changeBillType(String type) async {
    if (controller.monthlyBillingLocked) {
      _log('billing=type_change_blocked reason=monthly_parking requested=$type');
      return;
    }
    if (type == '정기' && _hasMonthlyLoaded && !_hasMonthlyParking) return;
    setState(() {
      controller.selectedBillType = type;
      controller.selectedBill = null;
      controller.selectedBasicStandard = 0;
      controller.selectedBasicAmount = 0;
      controller.selectedAddStandard = 0;
      controller.selectedAddAmount = 0;
      if (type != '정기') controller.countTypeController.clear();
      _statusLookupGeneration++;
      _monthlyLookupGeneration++;
      controller.resetStatusLookupToIdle();
    });
    _log('billing=type_changed type=$type');
    if (type == '정기') {
      await _handleMonthlySelectedFetchAndApply();
    } else {
      await _lookupGeneralStatusForCurrentPlate(preserveBillingType: true);
    }
  }

  void _selectGeneralBill(String value) {
    if (controller.monthlyBillingLocked) {
      _log('billing=value_change_blocked reason=monthly_parking value=${value.trim()}');
      return;
    }
    final billState = context.read<BillState>();
    BillModel? selected;
    for (final bill in billState.generalBills) {
      if (bill.countType.trim() == value.trim()) {
        selected = bill;
        break;
      }
    }
    setState(() {
      controller.selectedBill = value.trim();
      if (selected != null) {
        controller.selectedBasicStandard = selected.basicStandard ?? 0;
        controller.selectedBasicAmount = selected.basicAmount ?? 0;
        controller.selectedAddStandard = selected.addStandard ?? 0;
        controller.selectedAddAmount = selected.addAmount ?? 0;
      }
    });
    _log(
      'billing=value_selected type=${controller.selectedBillType} value=${value.trim()} source=local_cache statusLookup=unchanged',
    );
  }

  String _variableBillingSummary() {
    if (!_hasVariableBillingSelection) return '';
    final value = controller.selectedBill!.trim();
    return '$value · ${controller.selectedBasicStandard}분 · ${controller.selectedBasicAmount}원';
  }

  String _regularBillingSummary() {
    if (!_hasRegularBillingSelection) return '';
    final value = controller.selectedBill?.trim().isNotEmpty == true
        ? controller.selectedBill!.trim()
        : controller.countTypeController.text.trim();
    return value;
  }

  List<PlateBillingDetailRow> _variableBillingDetailRows() {
    if (!_hasVariableBillingSelection) {
      return const <PlateBillingDetailRow>[];
    }
    final value = controller.selectedBill!.trim();
    return <PlateBillingDetailRow>[
      const PlateBillingDetailRow(label: '정산 유형', value: '변동'),
      PlateBillingDetailRow(label: '적용 기준', value: value),
      PlateBillingDetailRow(
        section: '기본',
        label: '시간',
        value: '${controller.selectedBasicStandard}분',
      ),
      PlateBillingDetailRow(
        label: '금액',
        value: '${controller.selectedBasicAmount}원',
      ),
      PlateBillingDetailRow(
        section: '추가',
        label: '시간',
        value: '${controller.selectedAddStandard}분',
      ),
      PlateBillingDetailRow(
        label: '금액',
        value: '${controller.selectedAddAmount}원',
      ),
    ];
  }

  String? get _statusError {
    switch (controller.statusLookupState) {
      case PlateStatusLookupState.failed:
        return '기존 상태 정보를 확인하지 못했습니다.';
      case PlateStatusLookupState.inactive:
        return '상태 정보의 유효기간을 다시 확인해야 합니다.';
      case PlateStatusLookupState.idle:
      case PlateStatusLookupState.loading:
      case PlateStatusLookupState.found:
      case PlateStatusLookupState.notFound:
        return null;
    }
  }

  Future<void> _retryStatusLookup() async {
    if (controller.selectedBillType == '정기') {
      await _handleMonthlySelectedFetchAndApply();
    } else {
      await _lookupGeneralStatusForCurrentPlate(forceRefresh: true);
    }
  }

  String _normalizeOcr(String value) {
    var result = value.trim().replaceAll(RegExp(r'\s+'), '');
    const replacements = <String, String>{
      'O': '0',
      'o': '0',
      'I': '1',
      'l': '1',
      'B': '8',
      'S': '5',
    };
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  String _normalizeMiddle(String value) {
    const replacements = <String, String>{
      '리': '러',
      '이': '어',
      '지': '저',
      '히': '허',
      '기': '거',
      '니': '너',
      '디': '더',
      '미': '머',
      '비': '버',
      '시': '서',
    };
    return replacements[value] ?? value;
  }

  bool _applyOcrPlate(String plate, {String? sessionId}) {
    final raw = _normalizeOcr(plate).replaceAll('-', '');
    final match = RegExp(r'^(\d{2,3})(.)(\d{4})$').firstMatch(raw);
    String front = '';
    String mid = '';
    String back = '';
    if (match != null) {
      front = match.group(1)!;
      mid = _normalizeMiddle(match.group(2)!);
      back = match.group(3)!;
    } else if (RegExp(r'^\d{7}$').hasMatch(raw)) {
      front = raw.substring(0, 3);
      back = raw.substring(3);
    } else if (RegExp(r'^\d{6}$').hasMatch(raw)) {
      front = raw.substring(0, 2);
      back = raw.substring(2);
    } else {
      _log('ocr=apply_rejected raw=$raw');
      return false;
    }

    controller.suppressOcrEditCount(true);
    final wasMonthlyLocked = controller.monthlyBillingLocked;
    setState(() {
      controller.isThreeDigit = front.length == 3;
      controller.controllerFrontDigit.text = front;
      controller.controllerMidDigit.text = mid;
      controller.controllerBackDigit.text = back;
      _monthlyLookupGeneration++;
      controller.unlockMonthlyBilling(clearSelection: true);
      controller.resetStatusLookupToIdle();
      _clearHistoryStatusCache();
    });
    if (wasMonthlyLocked) {
      _log('monthly_lock=reset source=ocr_plate_change');
    }
    controller.suppressOcrEditCount(false);
    if (sessionId != null && sessionId.isNotEmpty) {
      controller.bindOcrSession(sessionId);
    } else {
      controller.clearOcrSession();
    }
    _syncIdentityDraftFromCommitted();
    final valid = controller.isInputValid();
    _log(
      'ocr=applied plate=${controller.buildPlateNumber()} valid=$valid midRequired=${mid.isEmpty}',
    );
    if (valid) {
      _lookupGeneralStatusForCurrentPlate();
    }
    return true;
  }

  PlateIdentityAuxiliaryResult _resolveLiveOcrResult(
      LiveOcrSessionResult result, {
        required String source,
      }) {
    var applied = false;
    var middleSuggestions = const <String>[];
    PlateIdentityFocusTarget focusTarget;
    if (result.plate?.isNotEmpty == true) {
      applied = _applyOcrPlate(
        result.plate!,
        sessionId: result.sessionId,
      );
      focusTarget = _resolveIdentityFocus();
    } else if (result.requiresMidCompletion &&
        result.weakFront != null &&
        result.weakBack != null) {
      applied = _applyOcrPlate(
        '${result.weakFront}${result.weakBack}',
        sessionId: result.sessionId,
      );
      middleSuggestions = List<String>.from(
        result.weakMidSuggestions,
        growable: false,
      );
      focusTarget = PlateIdentityFocusTarget.middle;
    } else {
      focusTarget = _resolveIdentityFocus();
    }
    final completePlate = result.plate?.trim().isNotEmpty == true &&
        applied &&
        controller.isInputValid() &&
        !result.requiresMidCompletion;
    final requiresManualCompletion = !completePlate;
    _syncControllerIdentityFocus(focusTarget);
    _log(
      'ocr=result sessionId=${result.sessionId} exitType=${result.exitType.name} plate=${result.plate ?? ''} attempts=${result.attemptCount} requiresMidCompletion=${result.requiresMidCompletion} applied=$applied completePlate=$completePlate manualCompletion=$requiresManualCompletion focus=${focusTarget.name} suggestions=${middleSuggestions.join('|')} source=$source',
      progress: completePlate ? .34 : .30,
    );
    _log(
      'ocr=followup_decision sessionId=${result.sessionId} exitType=${result.exitType.name} openIdentityEditor=$requiresManualCompletion source=$source',
    );
    if (_editorTrace?.developerMode == true) {
      final logs = result.logs;
      final max = logs.length.clamp(0, 40).toInt();
      if (max > 0) {
        _log('ocr=diagnostic\n${logs.take(max).join('\n')}');
      }
    }
    return PlateIdentityAuxiliaryResult(
      applied: applied,
      focusTarget: focusTarget,
      middleSuggestions: middleSuggestions,
      requiresManualCompletion: requiresManualCompletion,
    );
  }

  Future<PlateIdentityAuxiliaryResult> _prepareLiveOcrExit(
      LiveOcrSessionResult result, {
        required String source,
        required Rect sourceRect,
        required LiveOcrSourceRectRouteController<LiveOcrSessionResult>
        routeController,
      }) async {
    final resolved = _resolveLiveOcrResult(result, source: source);
    await _handleLiveOcrFollowup(
      resolved,
      source: source,
      allowScannerActive: true,
    );
    if (!mounted) return resolved;
    await _waitForSideDockSettled();
    if (!mounted) return resolved;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (resolved.requiresManualCompletion && !reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return resolved;
    }
    widget.sideDockPresentationController?.show();
    final destinationKey = resolved.requiresManualCompletion
        ? _identityPlateAnchorKey
        : _overviewPlateAnchorKey;
    final destination = await _waitForTargetRect(destinationKey) ?? sourceRect;
    routeController.setExitTargetRect(destination);
    _log(
      'ocr=transition_reverse_prepare source=$source destination=${resolved.requiresManualCompletion ? 'identity_editor' : 'overview_plate'} rect=${_rectDebug(destination)}',
      progress: .35,
    );
    return resolved;
  }

  Future<PlateIdentityAuxiliaryResult?> _openLiveScanner({
    bool automatic = false,
    String source = 'side_dock',
    Rect? sourceRect,
  }) async {
    if (!mounted) return null;
    if (_scannerActive) {
      _log('ocr=open_skipped reason=already_active automatic=$automatic source=$source');
      return null;
    }
    if (automatic && _openedScannerOnce) {
      _log('ocr=open_skipped reason=automatic_already_opened source=$source');
      return null;
    }
    _openedScannerOnce = true;
    _scannerActive = true;
    final sessionId = const Uuid().v4();
    final routeContext = context;
    final reduceMotion =
        MediaQuery.maybeOf(routeContext)?.disableAnimations ?? false;
    final entryRect = sourceRect ?? _fallbackOcrSourceRect();
    final morphController = LiveOcrSourceRectRouteController<LiveOcrSessionResult>(
      entrySourceRect: entryRect,
      reduceMotion: reduceMotion,
    );
    PlateIdentityAuxiliaryResult? preparedResult;
    _log(
      'ocr=open sessionId=$sessionId automatic=$automatic source=$source sourceRect=${_rectDebug(entryRect)} transition=source_rect_crop',
    );
    try {
      final route = morphController.buildRoute(
        builder: (_) => LiveOcrPage(
          sessionId: sessionId,
          onExitPreparing: (result) async {
            preparedResult = await _prepareLiveOcrExit(
              result,
              source: source,
              sourceRect: entryRect,
              routeController: morphController,
            );
          },
        ),
      );
      final result =
      await Navigator.of(routeContext).push<LiveOcrSessionResult>(route);
      await route.completed;
      if (!mounted) return preparedResult;
      _log(
        'ocr=route_closed sessionId=$sessionId automatic=$automatic source=$source transition=reverse_complete',
      );
      if (preparedResult != null) return preparedResult;
      widget.sideDockPresentationController?.show();
      if (result == null) {
        _log(
          'ocr=closed_without_result sessionId=$sessionId automatic=$automatic source=$source manualCompletion=true',
        );
        final focusTarget = _resolveIdentityFocus();
        _syncControllerIdentityFocus(focusTarget);
        final fallback = PlateIdentityAuxiliaryResult(
          applied: false,
          focusTarget: focusTarget,
          requiresManualCompletion: true,
        );
        await _handleLiveOcrFollowup(
          fallback,
          source: '${source}_fallback',
          allowScannerActive: true,
        );
        return fallback;
      }
      final fallback = _resolveLiveOcrResult(result, source: '${source}_fallback');
      await _handleLiveOcrFollowup(
        fallback,
        source: '${source}_fallback',
        allowScannerActive: true,
      );
      return fallback;
    } finally {
      morphController.dispose();
      _scannerActive = false;
    }
  }

  Future<void> _showDeveloperStatus() async {
    final trace = _editorTrace;
    if (trace == null || !trace.developerMode || !mounted) return;
    _log('developer_status_dialog=open source=header_action');
    await trace.showSnapshotStatusDialog(
      context,
      title: '차량 등록 디버그 상태',
      description: '현재까지 기록된 등록 흐름을 확인합니다.',
    );
  }

  Future<void> _handleSubmit() async {
    if (_busy || _hasPendingWorkspaceDraft) return;
    _log(
      'register=start plate=${controller.buildPlateNumber()} area=${context.read<AreaState>().currentArea}',
      progress: .72,
    );
    final success = await controller.submitPlateEntry(
      context,
          () {
        if (mounted) setState(() {});
      },
      onDebug: _log,
    );
    if (!mounted) return;
    if (!success) {
      _log('register=failed', progress: .88);
      if (_editorTrace?.developerMode == true) {
        await _editorTrace!.showSnapshotStatusDialog(
          context,
          title: '차량 등록 실패 상태',
          description: '등록이 중단된 시점까지의 흐름을 확인합니다.',
          failure: true,
        );
      }
      return;
    }
    _log('register=success', progress: .98);
    final trace = _editorTrace;
    if (trace != null) {
      await trace.succeed('차량 등록이 완료되었습니다.');
      if (trace.developerMode && mounted) {
        await trace.showStatusDialog(context);
      }
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<bool> _confirmDiscard() async {
    if (!mounted) return false;
    final result = await showCommonOverlayDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        return CommonDialogFrame(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: tokens.warning,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '차량 등록을 종료할까요?',
                        style: Theme.of(dialogContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '입력한 정보와 촬영한 사진은 저장되지 않습니다.',
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CommonButton(
                        label: '계속 입력',
                        variant: CommonButtonVariant.secondary,
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CommonButton(
                        label: '종료',
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result == true;
  }

  Future<void> _requestClose({required String source}) async {
    if (_busy) return;
    _log('close=request source=$source hasContent=$_hasEnteredContent');
    if (_hasEnteredContent) {
      final discard = await _confirmDiscard();
      if (!mounted || !discard) return;
      _log('close=discard_confirmed source=$source');
    }
    final trace = _editorTrace;
    if (trace != null) {
      await trace.succeed('차량 등록 Side Dock이 닫혔습니다.');
      if (trace.developerMode && mounted) {
        await trace.showStatusDialog(context);
      }
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  PlateEditorSectionStatus _identityStatus(
      InputPlateRegistrationPolicy registration,
      ) {
    if (controller.statusLookupInProgress) {
      return PlateEditorSectionStatus.loading;
    }
    if (_statusError != null) return PlateEditorSectionStatus.error;
    if (registration.identityComplete && registration.statusReady) {
      return PlateEditorSectionStatus.complete;
    }
    return PlateEditorSectionStatus.incomplete;
  }

  bool get _hasVariableBillingSelection =>
      controller.selectedBillType == '변동' &&
          controller.selectedBill?.trim().isNotEmpty == true;

  bool get _hasRegularBillingSelection =>
      controller.selectedBillType == '정기' &&
          (controller.selectedBill?.trim().isNotEmpty == true ||
              controller.countTypeController.text.trim().isNotEmpty);

  Future<void> _handleOverviewWorkspaceTap(
      PlateEditorWorkspace workspace,
      PlateEditorPolicy policy,
      ) async {
    if (controller.monthlyBillingLocked &&
        _isMonthlyLockedWorkspace(workspace)) {
      _log(
        'overview=row_tap_blocked workspace=${workspace.name} reason=monthly_parking',
      );
      return;
    }
    if (_busy || workspace == PlateEditorWorkspace.overview) return;
    if (!policy.supports(workspace)) return;

    switch (workspace) {
      case PlateEditorWorkspace.parking:
        final hasParking =
            controller.locationController.text.trim().isNotEmpty ||
                controller.selectedParkingPriorities.isNotEmpty;
        if (hasParking) {
          _log('overview=row_tap workspace=parking action=clear');
          _clearParkingLocation();
          return;
        }
        break;
      case PlateEditorWorkspace.sector:
        final hasSector =
            controller.selectedSectorId?.trim().isNotEmpty == true ||
                controller.selectedSectorName?.trim().isNotEmpty == true;
        if (hasSector) {
          _log('overview=row_tap workspace=sector action=clear');
          _clearSectorSelection();
          return;
        }
        break;
      case PlateEditorWorkspace.variableBilling:
        if (_hasVariableBillingSelection) {
          _log('overview=row_tap workspace=variableBilling action=clear');
          await _clearBillingSelection('변동');
          return;
        }
        break;
      case PlateEditorWorkspace.regularBilling:
        _log(
          'overview=row_tap_ignored workspace=regularBilling reason=read_only',
        );
        return;
      case PlateEditorWorkspace.vehicleIdentity:
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

  Widget _buildOverview(
      PlateEditorPolicy policy,
      InputPlateRegistrationPolicy registration,
      ) {
    final locations = context.watch<LocationState>().locations;
    final memo = controller.customStatusController.text.trim();
    final hasParking = controller.locationController.text.trim().isNotEmpty ||
        controller.selectedParkingPriorities.isNotEmpty;
    final sections = <Widget>[
      PlateEditorVehicleIdentitySection(
        region: controller.dropdownValue,
        plate: controller.isInputValid() ? controller.buildPlateNumber() : '',
        regionStatus: controller.dropdownValue.trim().isEmpty
            ? PlateEditorSectionStatus.incomplete
            : PlateEditorSectionStatus.complete,
        plateStatus: _identityStatus(registration),
        onRegionTap: () => unawaited(_openRegionPicker()),
        plateAnchorKey: _overviewPlateAnchorKey,
        onPlateTap: () => unawaited(
          _handleOverviewWorkspaceTap(
            PlateEditorWorkspace.vehicleIdentity,
            policy,
          ),
        ),
      ),
      PlateEditorOverviewSection(
        icon: Icons.local_parking_rounded,
        title: '주차 구역',
        value: controller.locationController.text.trim().isEmpty
            ? ''
            : plateParkingOverviewLocation(
          controller.locationController.text,
          locations: locations,
        ),
        status: hasParking
            ? PlateEditorSectionStatus.complete
            : registration.parkingRequired
            ? PlateEditorSectionStatus.incomplete
            : PlateEditorSectionStatus.optional,
        onTap: () => unawaited(
          _handleOverviewWorkspaceTap(
            PlateEditorWorkspace.parking,
            policy,
          ),
        ),
      ),
      PlateEditorOverviewPhotoSection(
        summary: '신규 ${controller.capturedImages.length}장',
        status: controller.capturedImages.isEmpty
            ? PlateEditorSectionStatus.none
            : PlateEditorSectionStatus.complete,
        onTap: () => unawaited(
          _handleOverviewWorkspaceTap(
            PlateEditorWorkspace.camera,
            policy,
          ),
        ),
      ),
      if (policy.hasSector)
        PlateEditorOverviewSection(
          icon: Icons.place_rounded,
          title: '방문 구역',
          value: controller.selectedSectorName?.trim().isNotEmpty == true
              ? controller.selectedSectorName!.trim()
              : '',
          status: registration.sectorComplete
              ? PlateEditorSectionStatus.complete
              : PlateEditorSectionStatus.incomplete,
          onTap: () => unawaited(
            _handleOverviewWorkspaceTap(
              PlateEditorWorkspace.sector,
              policy,
            ),
          ),
        ),
      if (policy.hasBill)
        PlateEditorOverviewSection(
          icon: Icons.receipt_long_rounded,
          title: '정산 유형',
          value: _variableBillingSummary(),
          enabled: !controller.monthlyBillingLocked,
          status: _hasVariableBillingSelection
              ? PlateEditorSectionStatus.complete
              : controller.selectedBillType == '변동' &&
              registration.billingRequired
              ? PlateEditorSectionStatus.incomplete
              : PlateEditorSectionStatus.none,
          onTap: () => unawaited(
            _handleOverviewWorkspaceTap(
              PlateEditorWorkspace.variableBilling,
              policy,
            ),
          ),
        ),
      if (policy.hasBill)
        PlateEditorOverviewSection(
          icon: Icons.calendar_month_rounded,
          title: '정기 등록',
          value: _regularBillingSummary(),
          enabled: !controller.monthlyBillingLocked,
          interactionEnabled: false,
          status: _hasRegularBillingSelection
              ? PlateEditorSectionStatus.complete
              : controller.selectedBillType == '정기' &&
              registration.billingRequired
              ? PlateEditorSectionStatus.incomplete
              : PlateEditorSectionStatus.none,
          onTap: null,
        ),
      PlateEditorOverviewSection(
        icon: _statusError == null
            ? Icons.notes_rounded
            : Icons.warning_amber_rounded,
        title: '상태 메모',
        enabled: !controller.monthlyBillingLocked,
        value: controller.statusLookupInProgress
            ? '상태 정보 확인 중'
            : _statusError != null
            ? _statusError!
            : memo,
        status: controller.statusLookupInProgress
            ? PlateEditorSectionStatus.loading
            : _statusError != null
            ? PlateEditorSectionStatus.error
            : memo.isEmpty
            ? PlateEditorSectionStatus.none
            : PlateEditorSectionStatus.complete,
        onTap: () => unawaited(
          _handleOverviewWorkspaceTap(
            PlateEditorWorkspace.memo,
            policy,
          ),
        ),
      ),
    ];

    return PlateEditorOverview(
      title: '차량 등록 정보',
      sections: sections,
    );
  }

  Future<void> _closeForInvalidParkingConfiguration(
    BuildContext dialogContext,
  ) async {
    _log(
      'parking_configuration=invalid reason=mixed_location_types action=close_input_side_dock',
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
    Navigator.of(context).pop(false);
  }

  void _closeEditorDialog(
      BuildContext dialogContext,
      PlateEditorWorkspace workspace, {
        required String reason,
      }) {
    _log('dialog=${workspace.name}_request_close reason=$reason');
    Navigator.of(dialogContext, rootNavigator: true).pop();
  }

  Widget _buildVariableBillingWorkspace(
      BuildContext dialogContext,
      StateSetter setDialogState,
      ) {
    final billState = context.read<BillState>();
    final options = billState.generalBills
        .map(
          (bill) => PlateBillingOption(
        value: bill.countType,
        detail:
        '${bill.basicStandard ?? 0}분 · ${bill.basicAmount ?? 0}원 · 추가 ${bill.addStandard ?? 0}분 ${bill.addAmount ?? 0}원',
      ),
    )
        .toList(growable: false);
    final value = _hasVariableBillingSelection
        ? controller.selectedBill!.trim()
        : '';
    return PlateBillingWorkspace(
      onExit: () => _closeEditorDialog(
        dialogContext,
        PlateEditorWorkspace.variableBilling,
        reason: 'variable_billing_exit',
      ),
      selectedType: '변동',
      selectedValue: value,
      title: '변동 정산',
      subtitle: '변동 정산',
      valueOptions: options,
      detailRows: _variableBillingDetailRows(),
      loading: billState.isLoading,
      onValueChanged: (selectedValue) {
        _selectGeneralBill(selectedValue);
        if (dialogContext.mounted) setDialogState(() {});
        if (!mounted) return;
        _log(
          'billing=variable_auto_applied value=${selectedValue.trim()}',
        );
        HapticFeedback.mediumImpact();
        if (!dialogContext.mounted) return;
        _closeEditorDialog(
          dialogContext,
          PlateEditorWorkspace.variableBilling,
          reason: 'variable_billing_auto_apply',
        );
      },
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
          currentLocation: controller.locationController.text.trim(),
          preferredParkingAreas: controller.selectedParkingPriorities,
          onLocationApplied: _applyParking,
          onClearLocation:
          widget.isMinorMode ? _clearParkingLocation : null,
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
          plateNumber: controller.isInputValid()
              ? controller.buildPlateNumber()
              : 'new_plate',
          initialCapturedImages: List<XFile>.from(controller.capturedImages),
          initialPreviewImages: _cameraInitialPreviewImages,
          initialPreviewIndex: _cameraInitialPreviewIndex,
          startInPreview: _cameraStartInPreview,
          onExit: () => _closeEditorDialog(
            dialogContext,
            PlateEditorWorkspace.camera,
            reason: 'camera_exit',
          ),
          onImageCaptured: (image) {
            if (controller.capturedImages.any((item) => item.path == image.path)) {
              return;
            }
            setState(() => controller.capturedImages.add(image));
            _log(
              'camera=captured path=${image.path} count=${controller.capturedImages.length}',
            );
          },
          onImageDeleted: (image) {
            setState(() {
              controller.capturedImages.removeWhere(
                    (candidate) => candidate.path == image.path,
              );
            });
            _log(
              'camera=deleted path=${image.path} count=${controller.capturedImages.length}',
            );
          },
          onDebug: _log,
        );
      case PlateEditorWorkspace.sector:
        return PlateSectorWorkspace(
          selectedId: controller.selectedSectorId,
          selectedName: controller.selectedSectorName,
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
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return _buildVariableBillingWorkspace(
              dialogContext,
              setDialogState,
            );
          },
        );
      case PlateEditorWorkspace.regularBilling:
        return const SizedBox.shrink();
      case PlateEditorWorkspace.memo:
        return PlateMemoWorkspace(
          controller: _memoDraftController,
          originalValue: controller.expectedOriginalStatus.customStatus,
          committedValue: controller.customStatusController.text,
          statusResolving: controller.statusLookupInProgress,
          statusError: _statusError,
          onRetry: _retryStatusLookup,
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final policy = PlateEditorPolicy.fromCapabilities(
      area: areaState.currentArea,
      capabilities: areaState.capabilitiesOfCurrentArea,
    );
    _syncPolicy(policy);
    final billState = context.watch<BillState>();
    final registration = InputPlateRegistrationPolicy.resolve(
      controller: controller,
      editorPolicy: policy,
      billState: billState,
    );
    final pending = _hasPendingWorkspaceDraft;
    final hasParkingLocation =
        controller.locationController.text.trim().isNotEmpty;
    final entryActionLabel = hasParkingLocation ? '입차 완료' : '입차 요청';
    final entryActionIcon = hasParkingLocation
        ? Icons.check_circle_outline_rounded
        : Icons.outbox_rounded;
    final entryActionVariant = hasParkingLocation
        ? CommonButtonVariant.success
        : CommonButtonVariant.destructive;
    final plate = controller.isInputValid() ? controller.buildPlateNumber() : '';

    return CommonUiScope(
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (didPop) return;
          if (_identityEditing) {
            _exitIdentityEditor(reason: 'system_back');
            return;
          }
          await _requestClose(source: 'system_back');
        },
        child: CommonSideDockFrame(
          title: _identityEditing
              ? '차량 식별정보'
              : plate.isEmpty
              ? '신규 차량'
              : plate,
          subtitle: _identityEditing ? '차량번호 입력' : '차량 등록',
          icon: _identityEditing
              ? Icons.badge_rounded
              : Icons.add_circle_rounded,
          closeEnabled: !_busy && !_identityAutoApplying,
          onClose: () {
            if (_identityEditing) {
              _exitIdentityEditor(reason: 'header_close');
              return;
            }
            _requestClose(source: 'header_close');
          },
          onHeaderTap: _identityEditing
              ? null
              : () => _enterIdentityEditor(source: 'header_identity'),
          headerAction: AnimatedSwitcher(
            duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                ? Duration.zero
                : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .88, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: _editorTrace?.developerMode == true
                ? CommonIconButton(
              key: const ValueKey<String>('input_plate_debug_action'),
              icon: Icons.bug_report_rounded,
              tooltip: '디버그 상태',
              size: 38,
              iconSize: 19,
              haptic: CommonHaptic.selection,
              onPressed: _showDeveloperStatus,
            )
                : const SizedBox.shrink(
              key: ValueKey<String>('input_plate_debug_action_hidden'),
            ),
          ),
          leadingRail: PlateEditorRail(
            enabled: !_busy && !_identityEditing,
            policy: policy,
            disabledWorkspaces: _disabledMonthlyWorkspaces,
            selectedWorkspace: _activeDialog,
            onSelected: (workspace) => _openEditorDialog(
              workspace,
              policy,
              source: 'rail',
            ),
            onLiveOcr: (sourceRect) =>
                unawaited(_openScannerFromRail(sourceRect)),
          ),
          collapseLeadingRail: _identityEditing,
          footer: _identityEditing
              ? null
              : PlateEditorFooter(
            actionLabel: entryActionLabel,
            actionIcon: entryActionIcon,
            actionVariant: entryActionVariant,
            preserveActionVariantWhenDisabled: true,
            loading: controller.isLoading,
            onPressed: _busy || pending || !registration.canSubmit
                ? null
                : _handleSubmit,
          ),
          child: AnimatedSwitcher(
            duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                ? Duration.zero
                : const Duration(milliseconds: 190),
            reverseDuration:
            MediaQuery.maybeOf(context)?.disableAnimations == true
                ? Duration.zero
                : const Duration(milliseconds: 150),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(.025, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _identityEditing
                ? PlateIdentityWorkspace(
              key: ValueKey<String>(
                'identity:${_identityInitialFocus.name}:${_identityMiddleSuggestions.join('|')}',
              ),
              frontController: _identityFrontDraftController,
              middleController: _identityMidDraftController,
              backController: _identityBackDraftController,
              pending: _identityPending,
              description: '차량번호의 앞자리, 한글, 뒷자리를 입력합니다.',
              initialThreeDigit: controller.isThreeDigit,
              initialFocusTarget: _identityInitialFocus,
              middleSuggestions: _identityMiddleSuggestions,
              plateAnchorKey: _identityPlateAnchorKey,
              onFocusTargetChanged: _syncControllerIdentityFocus,
              onAutoApply: _applyIdentityDraft,
              onExit: () =>
                  _exitIdentityEditor(reason: 'workspace_back'),
              onDebug: _log,
            )
                : KeyedSubtree(
              key: const ValueKey<String>('input_overview'),
              child: _buildOverview(policy, registration),
            ),
          ),
        ),
      ),
    );
  }
}
