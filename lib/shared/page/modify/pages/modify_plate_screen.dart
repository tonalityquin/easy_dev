import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/models/capability.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/sector/applications/sector_state.dart';
import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/models/plate_model.dart';
import '../../../plate/widgets/action_trace_dialog.dart';
import '../../input/pages/sheets/input_location_bottom_sheet.dart';
import '../../input/pages/sheets/input_sector_selection_sheet.dart';
import '../controllers/modify_plate_controller.dart';
import 'prompt_modify_ui.dart';
import 'sheets/modify_bottom_navigation.dart';
import 'sheets/modify_camera_preview_dialog.dart';
import 'widgets/buttons/modify_animated_action_button.dart';
import 'widgets/buttons/modify_animated_parking_button.dart';
import 'widgets/buttons/modify_animated_photo_button.dart';
import 'widgets/modify_location_section.dart';
import 'widgets/modify_photo_section.dart';
import 'widgets/modify_status_custom_section.dart';
import 'widgets/modify_sector_section.dart';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final l1 = la >= lb ? la : lb;
  final l2 = la >= lb ? lb : la;
  return (l1 + .05) / (l2 + .05);
}

Color _resolveLogoTint({
  required Color background,
  required Color preferred,
  required Color fallback,
}) {
  if (_contrastRatio(preferred, background) >= 3) return preferred;
  return fallback;
}

class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
    required this.assetPath,
    required this.height,
    required this.preferredColor,
    required this.fallbackColor,
  });

  final String assetPath;
  final double height;
  final Color preferredColor;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    final tint = _resolveLogoTint(
      background: background,
      preferred: preferredColor,
      fallback: fallbackColor,
    );
    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

class ModifyPlateScreen extends StatefulWidget {
  const ModifyPlateScreen({
    super.key,
    required this.plate,
    required this.collectionKey,
  });

  final PlateModel plate;
  final PlateType collectionKey;

  @override
  State<ModifyPlateScreen> createState() => _ModifyPlateScreenState();
}

class _ModifyPlateScreenState extends State<ModifyPlateScreen> {
  static const String screenTag = 'plate modify';
  static const bool _kShowActionTrace =
      bool.fromEnvironment('PW_SHOW_ACTION_TRACE', defaultValue: false);
  static const String _kScreenTagAsset = 'assets/images/pelican_text.png';
  static const double _kScreenTagHeight = 54;
  static const String _kBottomBrandAsset =
      'assets/images/ParkinWorkin_text.png';
  static const double _kBottomBrandHeight = 48;
  static const double _sheetClosed = .16;
  static const double _sheetOpened = 1;

  late final ModifyPlateController _controller;

  final TextEditingController controllerFrontdigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final List<XFile> _capturedImages = <XFile>[];
  final List<String> _existingImageUrls = <String>[];
  final ScrollController _sheetContentController = ScrollController();

  bool isLoading = false;
  bool _sheetOpen = false;
  bool _sheetAnimating = false;
  bool _sectorSelecting = false;
  bool _statusContextResolving = true;
  String? _statusContextError;

  @override
  void initState() {
    super.initState();
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
    );
    _controller.initializePlate();
    _controller.initializeFieldValues();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveStatusContext();
    });
  }

  Future<void> _resolveStatusContext() async {
    if (!mounted) return;
    setState(() {
      _statusContextResolving = true;
      _statusContextError = null;
    });
    try {
      await _controller.resolveStatusContext();
      if (!mounted) return;
      setState(() {
        _statusContextResolving = false;
        _statusContextError = null;
      });
    } catch (error, stackTrace) {
      debugPrint(
        '[ModifyPlateScreen][StatusContext] plate=${widget.plate.plateNumber} '
        'resolved=false error=$error',
      );
      if (!mounted) return;
      setState(() {
        _statusContextResolving = false;
        _statusContextError = error.toString();
      });
      final trace = await DeveloperOperationTrace.start(
        context: context,
        title: '상태 저장 범위 확인',
        initialMessage: '상태 메모의 최신 정보와 저장 범위를 확인하고 있습니다.',
        usePromptUi: true,
        developerModeMessage:
            '개발자 모드 ON: 범위 확인 실패 로그를 복사할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: 범위 확인 실패 로그를 콘솔에 기록합니다.',
      );
      trace.log(
        'plate=${widget.plate.plateNumber} area=${widget.plate.area} '
        'resolved=false',
        progress: .62,
      );
      await trace.fail(
        '상태 메모 저장 범위를 확인하지 못했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _animateSheet({
    required bool open,
    required String source,
    bool showDeveloperStatus = true,
  }) async {
    if (_sheetAnimating || _sheetOpen == open) {
      debugPrint(
        '[ModifyPlateScreen][TouchSheet] ignored source=$source '
        'open=$open animating=$_sheetAnimating current=$_sheetOpen',
      );
      return;
    }

    final previousOpen = _sheetOpen;
    final target = open ? _sheetOpened : _sheetClosed;
    DeveloperOperationTrace? trace;

    if (mounted) {
      setState(() {
        _sheetAnimating = true;
        _sheetOpen = open;
      });
    }

    try {
      if (showDeveloperStatus && mounted) {
        trace = await DeveloperOperationTrace.start(
          context: context,
          title: '번호판 수정 추가 정보 카드',
          initialMessage: open
              ? '터치로 정산 및 상태 카드를 열고 있습니다.'
              : '터치로 정산 및 상태 카드를 닫고 있습니다.',
          usePromptUi: true,
          developerModeMessage:
              '개발자 모드 ON: 카드 제어 로그를 복사할 수 있습니다.',
          standardModeMessage:
              '개발자 모드 OFF: 터치 전용 카드 전환을 실행합니다.',
        );
        trace.log(
          'screen=ModifyPlateScreen source=$source '
          'target=${open ? 'open' : 'closed'} '
          'plate=${widget.plate.plateNumber}',
          progress: .24,
        );
        final areaState = context.read<AreaState>();
        final sectorVisible = areaState.capabilitiesOfCurrentArea.contains(
          Capability.sector,
        );
        trace.log(
          'sectorCardVisible=$sectorVisible area=${areaState.currentArea.trim()} '
          'sectorId=${_controller.selectedSectorId ?? ''} '
          'sectorName=${_controller.selectedSectorName ?? ''} '
          'layout=정산유형상단 firebaseRead=false',
          progress: .42,
        );
      } else {
        final areaState = context.read<AreaState>();
        final sectorVisible = areaState.capabilitiesOfCurrentArea.contains(
          Capability.sector,
        );
        debugPrint(
          '[ModifyPlateScreen][TouchSheet] source=$source '
          'target=${open ? 'open' : 'closed'} '
          'sectorCardVisible=$sectorVisible area=${areaState.currentArea.trim()} '
          'sectorId=${_controller.selectedSectorId ?? ''} '
          'sectorName=${_controller.selectedSectorName ?? ''} firebaseRead=false',
        );
      }

      await HapticFeedback.selectionClick();

      if (!open && _sheetContentController.hasClients) {
        _sheetContentController.jumpTo(0);
      }

      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (!reduceMotion) {
        await Future<void>.delayed(PromptUiMotion.layout);
      }

      trace?.log(
        '터치 전용 카드 위치 적용 완료: size=$target layout=AnimatedPositioned dragEnabled=false controllerRequired=false',
        progress: .82,
      );
      if (trace != null) {
        await trace.succeed(
          open
              ? '정산 및 상태 카드가 열렸습니다.'
              : '정산 및 상태 카드가 닫혔습니다.',
        );
      } else {
        debugPrint(
          '[ModifyPlateScreen][TouchSheet] completed '
          'target=${open ? 'open' : 'closed'} size=$target',
        );
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _sheetOpen = previousOpen);
      }

      if (trace != null) {
        await trace.fail(
          '정산 및 상태 카드 전환에 실패했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      } else {
        debugPrint(
          '[ModifyPlateScreen][TouchSheet] failed error=$error\n$stackTrace',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sheetAnimating = false);
      }
    }
  }

  Future<void> _toggleSheet({String source = 'toggle_header'}) {
    return _animateSheet(
      open: !_sheetOpen,
      source: source,
    );
  }

  Future<void> _handleModifyAction() async {
    if (_statusContextResolving || isLoading) return;
    if (_statusContextError != null ||
        !_controller.statusContextResolved) {
      await _resolveStatusContext();
      if (!mounted ||
          _statusContextError != null ||
          !_controller.statusContextResolved) {
        return;
      }
    }
    setState(() => isLoading = true);
    DeveloperOperationTrace? developerTrace;
    try {
      if (_kShowActionTrace) {
        await ActionTraceDialog.showAndRun(
          context,
          title: '수정 버튼 실행 로그',
          task: (trace) async {
            final success = await _controller.handleAction(
              trace: trace,
            );
            trace.add('handleAction result=$success');
          },
        );
        return;
      }

      final areaState = context.read<AreaState>();
      final canUseSector = areaState.capabilitiesOfCurrentArea.contains(
        Capability.sector,
      );
      developerTrace = await DeveloperOperationTrace.start(
        context: context,
        title: '번호판 수정 저장',
        initialMessage: '번호판 수정 정보를 저장하고 있습니다.',
        usePromptUi: true,
        developerModeMessage:
            '개발자 모드 ON: 저장 로그를 debugPrint 코드로 복사할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: 저장 로그를 콘솔에 기록합니다.',
      );
      developerTrace.log(
        'screen=ModifyPlateScreen plate=${widget.plate.plateNumber} '
        'area=${areaState.currentArea.trim()}',
        progress: .14,
      );
      developerTrace.log(
        'capability.sector=$canUseSector '
        'sectorCardVisible=$canUseSector '
        'sectorId=${_controller.selectedSectorId ?? ''} '
        'sectorName=${_controller.selectedSectorName ?? ''}',
        progress: .3,
      );
      developerTrace.log(
        'sectorSource=local-ui firebaseRead=false firebaseWrite=submit-with-plate',
        progress: .44,
      );
      final statusDraft = _controller.statusDraft;
      developerTrace.log(
        'statusMemoLength=${statusDraft.customStatus.length} '
        'statusChanged=${_controller.hasStatusChanges} '
        'statusDeletePending=${_controller.statusMarkedForDeletion} '
        'statusContextResolved=${_controller.statusContextResolved} '
        'statusScope=${_controller.statusScope?.name ?? 'unresolved'}',
        progress: .58,
      );

      final success = await _controller.handleAction();
      developerTrace.log('handleAction result=$success', progress: .88);
      if (success) {
        await developerTrace.succeed(
          canUseSector
              ? '방문 구역을 포함한 차량 수정 저장이 완료되었습니다.'
              : '방문 구역 기능이 숨겨진 상태로 차량 수정 저장이 완료되었습니다.',
        );
      } else {
        await developerTrace.fail('차량 수정 저장이 완료되지 않았습니다.');
      }

      if (success && mounted) {
        Navigator.pop(context);
      }
    } catch (error, stackTrace) {
      if (developerTrace != null) {
        await developerTrace.fail(
          '차량 수정 저장에 실패했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (mounted) {
        showFailedSnackbar(
          context,
          '수정 실패: $error',
          usePromptUi: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _showCameraPreviewDialog() async {
    if (!mounted) return;
    await showPromptOverlayDialog<void>(
      context: context,
      builder: (dialogContext) {
        return SizedBox.expand(
          child: ModifyCameraPreviewDialog(
            onImageCaptured: (image) {
              if (!mounted) return;
              setState(() => _controller.capturedImages.add(image));
            },
          ),
        );
      },
    );
  }

  List<String> _platePreferredParkingAreas() {
    return _controller.selectedParkingPriorities;
  }

  Future<void> _selectParkingLocation() async {
    await InputLocationBottomSheet.show(
      context,
      _controller.locationController,
      (location) {
        if (!mounted) return;
        setState(() {
          _controller.locationController.text = location;
          _controller.isLocationSelected = true;
        });
      },
      preferredParkingAreas: _platePreferredParkingAreas(),
      usePromptUi: true,
    );
  }

  Future<void> _showSectorOperationStatus({
    required String result,
    required bool success,
    required String area,
    required bool canUseSector,
    required String previousSectorId,
    required String previousSectorName,
    required String selectedSectorId,
    required String selectedSectorName,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (!mounted) {
      debugPrint(
        '[ModifyPlateScreen][Sector] result=$result area=$area '
        'canUseSector=$canUseSector previousSectorId=$previousSectorId '
        'previousSectorName=$previousSectorName selectedSectorId=$selectedSectorId '
        'selectedSectorName=$selectedSectorName firebaseRead=false',
      );
      return;
    }

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '번호판 수정 방문 구역',
      initialMessage: result,
      usePromptUi: true,
      developerModeMessage:
          '개발자 모드 ON: 방문 구역 변경 로그를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 방문 구역 변경 로그를 콘솔에 기록합니다.',
    );
    trace.log(
      'screen=ModifyPlateScreen plate=${widget.plate.plateNumber} area=$area',
      progress: .18,
    );
    trace.log(
      'capability.sector=$canUseSector source=AreaState firebaseRead=false',
      progress: .34,
    );
    trace.log(
      'previousSectorId=$previousSectorId previousSectorName=$previousSectorName',
      progress: .52,
    );
    trace.log(
      'selectedSectorId=$selectedSectorId selectedSectorName=$selectedSectorName',
      progress: .7,
    );
    trace.log(
      'source=SectorState layout=정산상태시트-정산유형상단 firebaseWrite=false',
      progress: .86,
    );

    if (success) {
      await trace.succeed(result);
      return;
    }

    await trace.fail(
      result,
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<void> _selectSector() async {
    if (_sectorSelecting || !mounted) return;

    final areaState = context.read<AreaState>();
    final area = areaState.currentArea.trim();
    final canUseSector = areaState.capabilitiesOfCurrentArea.contains(
      Capability.sector,
    );
    final previousSectorId = _controller.selectedSectorId?.trim() ?? '';
    final previousSectorName = _controller.selectedSectorName?.trim() ?? '';

    setState(() => _sectorSelecting = true);

    try {
      debugPrint(
        '[ModifyPlateScreen][Sector] open plate=${widget.plate.plateNumber} '
        'area=$area canUseSector=$canUseSector previousSectorId=$previousSectorId '
        'previousSectorName=$previousSectorName',
      );

      if (!canUseSector) {
        await _showSectorOperationStatus(
          result: '현재 지역은 방문 구역 기능을 사용하지 않아 선택 영역을 숨깁니다.',
          success: true,
          area: area,
          canUseSector: false,
          previousSectorId: previousSectorId,
          previousSectorName: previousSectorName,
          selectedSectorId: previousSectorId,
          selectedSectorName: previousSectorName,
        );
        return;
      }

      final sectorState = context.read<SectorState>();
      if (sectorState.isBusy) {
        if (mounted) {
          showFailedSnackbar(
            context,
            '방문 구역 정보를 준비하고 있습니다.',
            usePromptUi: true,
          );
        }
        await _showSectorOperationStatus(
          result: '방문 구역 로컬 데이터가 준비 중이어서 변경을 중단했습니다.',
          success: false,
          area: area,
          canUseSector: true,
          previousSectorId: previousSectorId,
          previousSectorName: previousSectorName,
          selectedSectorId: previousSectorId,
          selectedSectorName: previousSectorName,
        );
        return;
      }

      final rawSectors = sectorState.sectors;
      final validSectors = rawSectors
          .where(
            (sector) =>
                sector.id.trim().isNotEmpty &&
                sector.name.trim().isNotEmpty &&
                sector.area.trim() == area,
          )
          .toList(growable: false);

      debugPrint(
        '[ModifyPlateScreen][Sector] cacheKey=${SectorState.cacheKeyForArea(area)} '
        'raw=${rawSectors.length} valid=${validSectors.length} firebaseRead=false',
      );

      if (rawSectors.length != validSectors.length || validSectors.isEmpty) {
        if (mounted) {
          showFailedSnackbar(
            context,
            '현재 지역의 방문 구역 정보가 없습니다.',
            usePromptUi: true,
          );
        }
        await _showSectorOperationStatus(
          result: '방문 구역 로컬 데이터 무결성 검증에 실패했습니다.',
          success: false,
          area: area,
          canUseSector: true,
          previousSectorId: previousSectorId,
          previousSectorName: previousSectorName,
          selectedSectorId: previousSectorId,
          selectedSectorName: previousSectorName,
        );
        return;
      }

      final selected = await InputSectorSelectionSheet.show(
        context: context,
        area: area,
        sectors: validSectors,
        initialSelectedId: previousSectorId.isEmpty ? null : previousSectorId,
      );

      if (!mounted) return;

      if (selected == null) {
        await _showSectorOperationStatus(
          result: '방문 구역 변경을 취소했습니다.',
          success: true,
          area: area,
          canUseSector: true,
          previousSectorId: previousSectorId,
          previousSectorName: previousSectorName,
          selectedSectorId: previousSectorId,
          selectedSectorName: previousSectorName,
        );
        return;
      }

      final currentArea = context.read<AreaState>().currentArea.trim();
      final currentSectors = context.read<SectorState>().sectors;
      final confirmed = currentSectors.where((item) {
        return item.id == selected.id &&
            item.area.trim() == currentArea &&
            item.name.trim() == selected.name.trim();
      }).toList(growable: false);

      if (currentArea != area || confirmed.length != 1) {
        showFailedSnackbar(
          context,
          '방문 구역 정보가 변경되어 다시 선택해야 합니다.',
          usePromptUi: true,
        );
        await _showSectorOperationStatus(
          result: '선택 결과 재검증에 실패했습니다.',
          success: false,
          area: currentArea,
          canUseSector: true,
          previousSectorId: previousSectorId,
          previousSectorName: previousSectorName,
          selectedSectorId: selected.id.trim(),
          selectedSectorName: selected.name.trim(),
        );
        return;
      }

      final resolved = confirmed.single;
      _controller.selectedSectorId = resolved.id.trim();
      _controller.selectedSectorName = resolved.name.trim();
      await HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {});
      }

      await _showSectorOperationStatus(
        result: '방문 구역 변경값을 수정 화면에 반영했습니다.',
        success: true,
        area: currentArea,
        canUseSector: true,
        previousSectorId: previousSectorId,
        previousSectorName: previousSectorName,
        selectedSectorId: resolved.id.trim(),
        selectedSectorName: resolved.name.trim(),
      );
    } catch (error, stackTrace) {
      if (mounted) {
        showFailedSnackbar(
          context,
          '방문 구역 변경 실패: $error',
          usePromptUi: true,
        );
      }
      await _showSectorOperationStatus(
        result: '방문 구역 변경 처리에 실패했습니다.',
        success: false,
        area: area,
        canUseSector: canUseSector,
        previousSectorId: previousSectorId,
        previousSectorName: previousSectorName,
        selectedSectorId: _controller.selectedSectorId?.trim() ?? '',
        selectedSectorName: _controller.selectedSectorName?.trim() ?? '',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() => _sectorSelecting = false);
      }
    }
  }

  @override
  void dispose() {
    _sheetContentController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildScreenTag(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return SafeArea(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: $screenTag',
              child: ExcludeSemantics(
                child: _BrandTintedLogo(
                  assetPath: _kScreenTagAsset,
                  height: _kScreenTagHeight,
                  preferredColor: tokens.textSecondary,
                  fallbackColor: tokens.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBrandLogo(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return Semantics(
      label: 'brand_logo: ParkinWorkin',
      child: ExcludeSemantics(
        child: _BrandTintedLogo(
          assetPath: _kBottomBrandAsset,
          height: _kBottomBrandHeight,
          preferredColor: tokens.textSecondary,
          fallbackColor: tokens.textPrimary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(builder: _buildPromptScreen),
    );
  }

  Widget _buildPromptScreen(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final viewInset = mediaQuery.viewInsets.bottom;
    final bottomSafePadding = 140 + viewInset;
    final iconBrightness = tokens.isDark ? Brightness.light : Brightness.dark;
    final readOnlyCountType = _controller.selectedBillCountType ??
        _controller.selectedBill ??
        widget.plate.billingType ??
        '-';
    final canUseSector = context
        .watch<AreaState>()
        .capabilitiesOfCurrentArea
        .contains(Capability.sector);

    return PopScope(
      canPop: !_sheetOpen && !_sheetAnimating,
      onPopInvoked: (didPop) async {
        if (didPop || !_sheetOpen || _sheetAnimating) return;
        await _animateSheet(
          open: false,
          source: 'system_back',
          showDeveloperStatus: false,
        );
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: tokens.surface,
        statusBarIconBrightness: iconBrightness,
        systemNavigationBarColor: tokens.surfaceRaised,
        systemNavigationBarIconBrightness: iconBrightness,
      ),
      child: Scaffold(
        backgroundColor: tokens.canvas,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          backgroundColor: tokens.surface,
          foregroundColor: tokens.textPrimary,
          elevation: 0,
          surfaceTintColor: tokens.transparent,
          shape: Border(
            bottom: BorderSide(color: tokens.borderSubtle),
          ),
          flexibleSpace: _buildScreenTag(context),
          title: Text(
            '번호판 수정',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      bottomSafePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ModifyLocationSection(
                          locationController: _controller.locationController,
                        ),
                        const SizedBox(height: 16),
                        ModifyPhotoSection(
                          capturedImages: _controller.capturedImages,
                          imageUrls: widget.plate.imageUrls ?? const <String>[],
                          plateNumber: widget.plate.plateNumber,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : PromptUiMotion.layout,
                  curve: PromptUiMotion.standard,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: constraints.maxHeight *
                      (_sheetOpen ? _sheetOpened : _sheetClosed),
                  child: Builder(
                    builder: (context) {
                    return AnimatedContainer(
                      duration: mediaQuery.disableAnimations
                          ? Duration.zero
                          : PromptUiMotion.selection,
                      curve: PromptUiMotion.standard,
                      decoration: BoxDecoration(
                        color: tokens.surfaceRaised,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(PromptUiShapes.sheet),
                        ),
                        border: Border.all(
                          color: _sheetOpen
                              ? tokens.accent
                              : tokens.borderSubtle,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: tokens.shadow,
                            blurRadius: 16,
                            offset: const Offset(0, -6),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: true,
                        bottom: false,
                        child: ListView(
                          controller: _sheetContentController,
                          physics: _sheetOpen
                              ? const ClampingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            116 + viewInset,
                          ),
                          children: [
                            Material(
                              color: tokens.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  PromptUiShapes.control,
                                ),
                                onTap: _sheetAnimating
                                    ? null
                                    : () => _toggleSheet(
                                          source: 'toggle_header',
                                        ),
                                child: SizedBox(
                                  height: 56,
                                  child: Row(
                                    children: [
                                      AnimatedContainer(
                                        duration: mediaQuery.disableAnimations
                                            ? Duration.zero
                                            : PromptUiMotion.selection,
                                        curve: PromptUiMotion.standard,
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: _sheetOpen
                                              ? tokens.accentContainer
                                              : tokens.surfaceOverlay,
                                          borderRadius: BorderRadius.circular(
                                            PromptUiShapes.control,
                                          ),
                                          border: Border.all(
                                            color: _sheetOpen
                                                ? tokens.accent.withOpacity(
                                                    tokens.isDark ? .54 : .36,
                                                  )
                                                : tokens.borderSubtle,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: AnimatedSwitcher(
                                          duration: mediaQuery.disableAnimations
                                              ? Duration.zero
                                              : PromptUiMotion.selection,
                                          child: _sheetAnimating
                                              ? SizedBox(
                                                  key: const ValueKey(
                                                    'modify_sheet_loading',
                                                  ),
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: tokens.accent,
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.tune_rounded,
                                                  key: const ValueKey(
                                                    'modify_sheet_tune',
                                                  ),
                                                  color: _sheetOpen
                                                      ? tokens
                                                          .onAccentContainer
                                                      : tokens.iconSecondary,
                                                  size: 20,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: AnimatedSwitcher(
                                          duration: mediaQuery.disableAnimations
                                              ? Duration.zero
                                              : PromptUiMotion.selection,
                                          child: Column(
                                            key: ValueKey(
                                              '${_sheetOpen}_$_sheetAnimating',
                                            ),
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _sheetAnimating
                                                    ? _sheetOpen
                                                        ? '정산 및 상태 여는 중'
                                                        : '정산 및 상태 닫는 중'
                                                    : _sheetOpen
                                                        ? '정산 및 상태 닫기'
                                                        : '정산 및 상태 보기',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      color: tokens.textPrimary,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                              Text(
                                                _sheetOpen
                                                    ? '이 헤더를 한 번 터치하면 닫힙니다.'
                                                    : '이 헤더를 한 번 터치하면 열립니다.',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          tokens.textSecondary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        widget.plate.plateNumber,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: tokens.textSecondary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(width: 6),
                                      AnimatedRotation(
                                        turns: _sheetOpen ? .5 : 0,
                                        duration: mediaQuery.disableAnimations
                                            ? Duration.zero
                                            : PromptUiMotion.selection,
                                        curve: PromptUiMotion.standard,
                                        child: Icon(
                                          Icons.expand_less_rounded,
                                          color: tokens.iconSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (canUseSector) ...[
                              ModifySectorSection(
                                sectorName: _controller.selectedSectorName,
                                isBusy: _sectorSelecting,
                                onPressed: _selectSector,
                              ),
                              const SizedBox(height: 16),
                            ],
                            _ReadOnlyBillSection(
                              billTypeLabel: _controller.selectedBillType,
                              countTypeLabel: readOnlyCountType,
                            ),
                            const SizedBox(height: 16),
                            AnimatedOpacity(
                              duration: mediaQuery.disableAnimations
                                  ? Duration.zero
                                  : PromptUiMotion.selection,
                              opacity: _statusContextResolving ? .62 : 1,
                              child: AbsorbPointer(
                                absorbing: _statusContextResolving ||
                                    _statusContextError != null,
                                child: PromptModifySectionCard(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                  const PromptModifySectionTitle(
                                    icon: Icons.edit_note_rounded,
                                    title: '추가 상태 메모',
                                    subtitle: '최대 20자까지 차량 상태를 기록합니다.',
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller:
                                        _controller.customStatusController,
                                    maxLength: 20,
                                    minLines: 2,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      labelText: '상태 메모',
                                      prefixIcon:
                                          Icon(Icons.notes_rounded),
                                    ),
                                    onChanged: (_) {
                                      _controller.handleStatusTextChanged();
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                  const SizedBox(height: 4),
                                      ModifyStatusCustomSection(
                                        originalCustomStatus: _controller
                                            .originalStatusDraft.customStatus,
                                        changed: _controller.hasStatusChanges,
                                        deletionPending:
                                            _controller.statusMarkedForDeletion,
                                        onClear: () {
                                          setState(_controller.clearStatusDraft);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: mediaQuery.disableAnimations
                                  ? Duration.zero
                                  : PromptUiMotion.selection,
                              child: _statusContextResolving
                                  ? const Padding(
                                      key: ValueKey<String>('status-resolving'),
                                      padding: EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text('최신 상태 정보와 저장 범위를 확인하고 있습니다.'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : _statusContextError != null
                                      ? Padding(
                                          key: const ValueKey<String>('status-error'),
                                          padding: const EdgeInsets.only(top: 10),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.warning_amber_rounded,
                                                color: tokens.warning,
                                              ),
                                              const SizedBox(width: 10),
                                              const Expanded(
                                                child: Text(
                                                  '최신 상태 정보를 확인하지 못했습니다. 수정 완료 시 다시 확인하며, 확인에 실패하면 저장하지 않습니다.',
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : const SizedBox.shrink(
                                          key: ValueKey<String>('status-ready'),
                                        ),
                            ),
                          ],
                        ),
                      ),
                    );
                  
                    },
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ModifyBottomNavigation(
              actionButton: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ModifyAnimatedPhotoButton(
                          onPressed: _showCameraPreviewDialog,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ModifyAnimatedParkingButton(
                          isLocationSelected:
                              _controller.isLocationSelected,
                          onPressed: _selectParkingLocation,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ModifyAnimatedActionButton(
                    isLoading: isLoading || _statusContextResolving,
                    isLocationSelected: _controller.isLocationSelected,
                    buttonLabel: '수정 완료',
                    onPressed: _handleModifyAction,
                  ),
                ],
              ),
            ),
            PromptAnimatedReveal(
              delay: const Duration(milliseconds: 120),
              offset: const Offset(0, .02),
              child: Container(
                color: tokens.surfaceRaised,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: _kBottomBrandHeight,
                    child: _buildBottomBrandLogo(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}

class _ReadOnlyBillSection extends StatelessWidget {
  const _ReadOnlyBillSection({
    required this.billTypeLabel,
    required this.countTypeLabel,
  });

  final String billTypeLabel;
  final String countTypeLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return PromptModifySectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PromptModifySectionTitle(
            icon: Icons.receipt_long_rounded,
            title: '정산 유형',
            subtitle: '현재 적용 중인 정산 정보이며 이 화면에서는 변경하지 않습니다.',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    countTypeLabel.trim().isEmpty ? '-' : countTypeLabel,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                    border: Border.all(
                      color: tokens.accent.withOpacity(
                        tokens.isDark ? .54 : .36,
                      ),
                    ),
                  ),
                  child: Text(
                    billTypeLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: tokens.onAccentContainer,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
