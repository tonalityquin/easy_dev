import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/models/plate_model.dart';
import '../../../plate/widgets/action_trace_dialog.dart';
import '../../input/pages/sheets/input_location_bottom_sheet.dart';
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
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  bool isLoading = false;
  bool _sheetOpen = false;
  bool _sheetStateUpdateScheduled = false;
  bool? _pendingSheetOpen;
  late List<String> selectedStatusNames;

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
    selectedStatusNames = List<String>.from(widget.plate.statusList);
    _sheetController.addListener(_handleSheetSizeChanged);
  }

  void _handleSheetSizeChanged() {
    try {
      final openNow =
          _sheetController.size >= ((_sheetClosed + _sheetOpened) / 2);
      if (openNow == _sheetOpen && _pendingSheetOpen == null) return;
      _pendingSheetOpen = openNow;
      if (_sheetStateUpdateScheduled) return;
      _sheetStateUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sheetStateUpdateScheduled = false;
        if (!mounted) return;
        final next = _pendingSheetOpen;
        _pendingSheetOpen = null;
        if (next == null || next == _sheetOpen) return;
        setState(() => _sheetOpen = next);
      });
    } catch (_) {}
  }

  Future<void> _animateSheet({required bool open}) async {
    final target = open ? _sheetOpened : _sheetClosed;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    try {
      if (reduceMotion) {
        _sheetController.jumpTo(target);
      } else {
        await _sheetController.animateTo(
          target,
          duration: PromptUiMotion.layout,
          curve: PromptUiMotion.standard,
        );
      }
      if (mounted && _sheetOpen != open) {
        setState(() => _sheetOpen = open);
      }
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _sheetController.jumpTo(target);
        } catch (_) {
          return;
        }
        if (mounted && _sheetOpen != open) {
          setState(() => _sheetOpen = open);
        }
      });
    }
  }

  void _toggleSheet() {
    _animateSheet(open: !_sheetOpen);
  }

  Future<void> _handleModifyAction() async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      if (_kShowActionTrace) {
        await ActionTraceDialog.showAndRun(
          context,
          title: '수정 버튼 실행 로그',
          task: (trace) async {
            final success = await _controller.handleAction(
              selectedStatusNames,
              trace: trace,
            );
            trace.add('handleAction result=$success');
          },
        );
        return;
      }
      final success = await _controller.handleAction(selectedStatusNames);
      if (success && mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
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

  @override
  void dispose() {
    _sheetController.removeListener(_handleSheetSizeChanged);
    _sheetController.dispose();
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
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
          builder: (context, _) {
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
                DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: _sheetClosed,
                  minChildSize: _sheetClosed,
                  maxChildSize: _sheetOpened,
                  snap: true,
                  snapSizes: const <double>[_sheetClosed, _sheetOpened],
                  builder: (context, scrollController) {
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
                          controller: scrollController,
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
                                onTap: _toggleSheet,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(top: 8, bottom: 12),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: tokens.handle,
                                          borderRadius: BorderRadius.circular(
                                            PromptUiShapes.pill,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: tokens.accentContainer,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                PromptUiShapes.control,
                                              ),
                                              border: Border.all(
                                                color: tokens.accent.withOpacity(
                                                  tokens.isDark ? .54 : .36,
                                                ),
                                              ),
                                            ),
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.tune_rounded,
                                              color: tokens.onAccentContainer,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: AnimatedSwitcher(
                                              duration: mediaQuery
                                                      .disableAnimations
                                                  ? Duration.zero
                                                  : PromptUiMotion.selection,
                                              child: Text(
                                                _sheetOpen
                                                    ? '정산 및 상태 닫기'
                                                    : '정산 및 상태 열기',
                                                key: ValueKey(_sheetOpen),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      color: tokens.textPrimary,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                            ),
                                          ),
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
                                            duration: mediaQuery
                                                    .disableAnimations
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
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _ReadOnlyBillSection(
                              billTypeLabel: _controller.selectedBillType,
                              countTypeLabel: readOnlyCountType,
                            ),
                            const SizedBox(height: 16),
                            PromptModifySectionCard(
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
                                  ),
                                  if (_controller.fetchedCustomStatus != null)
                                    ModifyStatusCustomSection(
                                      customStatus:
                                          _controller.fetchedCustomStatus!,
                                      onDelete: () async {
                                        try {
                                          await _controller
                                              .deleteCustomStatusFromFirestore(
                                            context,
                                          );
                                          if (!mounted) return;
                                          setState(() {
                                            _controller.fetchedCustomStatus =
                                                null;
                                            _controller.customStatusController
                                                .clear();
                                            selectedStatusNames = <String>[];
                                          });
                                        } catch (error) {
                                          if (mounted) {
                                            showFailedSnackbar(
                                              context,
                                              '상태 메모 삭제 실패: $error',
                                              usePromptUi: true,
                                            );
                                          }
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
                    isLoading: isLoading,
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
