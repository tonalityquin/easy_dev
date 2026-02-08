import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../../models/plate_model.dart';
import '../../../enums/plate_type.dart';

import 'double_modify_plate_controller.dart';
import 'sections/double_modify_location_section.dart';
import 'sections/double_modify_photo_section.dart';
import 'sections/double_modify_plate_section.dart';
import 'sections/double_modify_status_custom_section.dart';

import 'utils/buttons/double_modify_animated_action_button.dart';
import 'utils/buttons/double_modify_animated_parking_button.dart';
import 'utils/buttons/double_modify_animated_photo_button.dart';

import 'widgets/double_modify_bottom_navigation.dart';
import 'widgets/double_modify_camera_preview_dialog.dart';
import 'widgets/double_modify_location_bottom_sheet.dart';
import '../../../utils/snackbar_helper.dart';
import 'utils/double_modify_camera_helper.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ 로고(PNG) 가독성 보장 유틸
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final l1 = la >= lb ? la : lb;
  final l2 = la >= lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

Color _resolveLogoTint({
  required Color background,
  required Color preferred,
  required Color fallback,
  double minContrast = 3.0,
}) {
  if (_contrastRatio(preferred, background) >= minContrast) return preferred;
  return fallback;
}

/// ✅ (경고 방지) required 파라미터만 사용하는 tint 로고 위젯
class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
    required this.assetPath,
    required this.height,
    required this.preferredColor,
    required this.fallbackColor,
    this.minContrast = 3.0,
  });

  final String assetPath;
  final double height;

  final Color preferredColor;
  final Color fallbackColor;
  final double minContrast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ✅ AppBar/Scaffold/Bottom 영역 전반에서 공통으로 사용할 대비 기준 배경색
    // - reference 코드와 동일하게 scaffoldBackgroundColor 사용
    final bg = theme.scaffoldBackgroundColor;

    final tint = _resolveLogoTint(
      background: bg,
      preferred: preferredColor,
      fallback: fallbackColor,
      minContrast: minContrast,
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

class DoubleModifyPlateScreen extends StatefulWidget {
  final PlateModel plate;
  final PlateType collectionKey;

  const DoubleModifyPlateScreen({
    super.key,
    required this.plate,
    required this.collectionKey,
  });

  @override
  State<DoubleModifyPlateScreen> createState() => _DoubleModifyPlateScreenState();
}

class _DoubleModifyPlateScreenState extends State<DoubleModifyPlateScreen> {
  static const String screenTag = 'plate modify';

  // ✅ (수정안) 좌측 상단 screenTag 텍스트 대신 사용할 이미지
  static const String _kScreenTagAsset = 'assets/images/pelican_text.png';

  // ✅ (요청) 좌측 상단 태그 이미지 크기 고정
  static const double _kScreenTagHeight = 54.0;

  // ✅ (수정안) 하단 브랜드 로고도 tint/대비 보장 적용
  static const String _kBottomBrandAsset = 'assets/images/ParkinWorkin_text.png';
  static const double _kBottomBrandHeight = 48.0;

  late DoubleModifyPlateController _controller;
  late DoubleModifyCameraHelper _cameraHelper;

  final TextEditingController controllerFrontdigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  final List<XFile> _capturedImages = [];
  final List<String> _existingImageUrls = [];

  bool isLoading = false;
  late List<String> selectedStatusNames;

  final DraggableScrollableController _sheetController = DraggableScrollableController();
  bool _sheetOpen = false;
  static const double _sheetClosed = 0.16;
  static const double _sheetOpened = 1.00;

  Future<void> _animateSheet({required bool open}) async {
    final target = open ? _sheetOpened : _sheetClosed;
    try {
      await _sheetController.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
      if (mounted) setState(() => _sheetOpen = open);
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sheetController.jumpTo(target);
        if (mounted) setState(() => _sheetOpen = open);
      });
    }
  }

  void _toggleSheet() {
    _animateSheet(open: !_sheetOpen);
  }

  @override
  void initState() {
    super.initState();

    _controller = DoubleModifyPlateController(
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

    _cameraHelper = DoubleModifyCameraHelper();

    _cameraHelper.initializeInputCamera().then((_) {
      if (mounted) setState(() {});
    });

    _controller.initializePlate();
    _controller.initializeFieldValues();

    selectedStatusNames = List<String>.from(widget.plate.statusList);

    _sheetController.addListener(() {
      try {
        final s = _sheetController.size;
        final bool openNow = s >= ((_sheetClosed + _sheetOpened) / 2);
        if (mounted && openNow != _sheetOpen) {
          setState(() => _sheetOpen = openNow);
        }
      } catch (_) {}
    });
  }

  void _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => DoubleModifyCameraPreviewDialog(
        onImageCaptured: (image) {
          setState(() {
            _controller.capturedImages.add(image);
          });
        },
      ),
    );

    await _cameraHelper.dispose();
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() {});
  }

  void _selectParkingLocation() {
    showDialog(
      context: context,
      builder: (_) => DoubleModifyLocationBottomSheet(
        locationController: _controller.locationController,
        onLocationSelected: (location) {
          setState(() {
            _controller.locationController.text = location;
            _controller.isLocationSelected = true;
          });
        },
      ),
    );
  }

  VoidCallback _buildLocationAction() {
    return _selectParkingLocation;
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _controller.dispose();
    _cameraHelper.dispose();
    super.dispose();
  }

  // ✅ (수정안) 좌측 상단(11시) 화면 태그: 텍스트 → pelican_text.png 이미지로 교체
  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ 기존 텍스트 태그 톤(onSurfaceVariant) 기반 tint 우선 시도
    // 대비 부족 시 onBackground로 폴백
    final tagPreferredTint = cs.onSurfaceVariant.withOpacity(0.80);

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
                  preferredColor: tagPreferredTint,
                  fallbackColor: cs.onBackground,
                  minContrast: 3.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ (수정안) 하단 ParkinWorkin_text 로고도 tint/대비 보장 적용
  Widget _buildBottomBrandLogo(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ 로고는 일반적으로 본문 텍스트보다 살짝 톤 다운된 onSurfaceVariant 계열이 자연스러움
    // 대비 부족 시 onBackground 폴백
    final preferred = cs.onSurfaceVariant.withOpacity(0.90);

    return Semantics(
      label: 'brand_logo: ParkinWorkin',
      child: ExcludeSemantics(
        child: _BrandTintedLogo(
          assetPath: _kBottomBrandAsset,
          height: _kBottomBrandHeight,
          preferredColor: preferred,
          fallbackColor: cs.onBackground,
          minContrast: 3.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafePadding = 140.0 + viewInset;

    final readOnlyCountType = _controller.selectedBillCountType ??
        _controller.selectedBill ??
        widget.plate.billingType ??
        '-';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1),
        ),

        // ✅ 기존과 동일하게 flexibleSpace에 좌측상단 태그 고정(텍스트→이미지)
        flexibleSpace: _buildScreenTag(context),

        title: Text(
          "번호판 수정",
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // 상단 본문
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafePadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DoubleModifyPlateSection(
                        dropdownValue: _controller.dropdownValue,
                        regions: _controller.regions,
                        controllerFrontdigit: controllerFrontdigit,
                        controllerMidDigit: controllerMidDigit,
                        controllerBackDigit: controllerBackDigit,
                        isEditable: false,
                        onRegionChanged: (region) {
                          setState(() => _controller.dropdownValue = region);
                        },
                      ),
                      const SizedBox(height: 32.0),
                      DoubleModifyLocationSection(locationController: _controller.locationController),
                      const SizedBox(height: 32.0),
                      DoubleModifyPhotoSection(
                        capturedImages: _controller.capturedImages,
                        imageUrls: widget.plate.imageUrls ?? [],
                        plateNumber: widget.plate.plateNumber,
                      ),
                    ],
                  ),
                ),
              ),

              // 하단 시트
              DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: _sheetClosed,
                minChildSize: _sheetClosed,
                maxChildSize: _sheetOpened,
                snap: true,
                snapSizes: const [_sheetClosed, _sheetOpened],
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withOpacity(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: true,
                      bottom: false,
                      child: ListView(
                        controller: scrollController,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          16 + 100 + viewInset,
                        ),
                        children: [
                          // 헤더(탭으로 열고/닫기)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleSheet,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 12),
                              child: Column(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: cs.outlineVariant.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _sheetOpen ? '정산 / 상태 (탭하여 닫기)' : '정산 / 상태 (탭하여 열기)',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                      Text(
                                        widget.plate.plateNumber,
                                        style: TextStyle(color: cs.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 정산(읽기 전용)
                          _ReadOnlyBillSection(
                            billTypeLabel: _controller.selectedBillType,
                            countTypeLabel: readOnlyCountType,
                          ),

                          const SizedBox(height: 24),

                          Text(
                            '추가 상태 메모 (최대 20자)',
                            style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _controller.customStatusController,
                            maxLength: 20,
                            decoration: InputDecoration(
                              hintText: '예: 뒷범퍼 손상',
                              filled: true,
                              fillColor: cs.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.primary, width: 1.4),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),

                          if (_controller.fetchedCustomStatus != null)
                            DoubleModifyStatusCustomSection(
                              customStatus: _controller.fetchedCustomStatus!,
                              onDelete: () async {
                                try {
                                  await _controller.deleteCustomStatusFromFirestore(context);
                                  if (!mounted) return;

                                  setState(() {
                                    _controller.fetchedCustomStatus = null;
                                    _controller.customStatusController.clear();
                                    selectedStatusNames = [];
                                  });
                                  showSuccessSnackbar(context, '자동 메모가 삭제되었습니다');
                                } catch (_) {
                                  if (!mounted) return;
                                  showFailedSnackbar(context, '삭제 실패. 다시 시도해주세요');
                                }
                              },
                            ),

                          const SizedBox(height: 8),
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
          DoubleModifyBottomNavigation(
            actionButton: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DoubleModifyAnimatedPhotoButton(onPressed: _showCameraPreviewDialog),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DoubleModifyAnimatedParkingButton(
                        isLocationSelected: _controller.isLocationSelected,
                        onPressed: _buildLocationAction(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                DoubleModifyAnimatedActionButton(
                  isLoading: isLoading,
                  isLocationSelected: _controller.isLocationSelected,
                  buttonLabel: '수정 완료',
                  onPressed: () async {
                    setState(() => isLoading = true);

                    await _controller.handleAction(() {
                      if (mounted) {
                        Navigator.pop(context);
                        showSuccessSnackbar(context, "수정이 완료되었습니다!");
                      }
                    }, selectedStatusNames);

                    if (mounted) setState(() => isLoading = false);
                  },
                ),
              ],
            ),
          ),

          // ✅ (수정안) 하단 ParkinWorkin_text 로고: tint/대비 보장 적용
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: _kBottomBrandHeight,
                child: _buildBottomBrandLogo(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyBillSection extends StatelessWidget {
  final String billTypeLabel;
  final String countTypeLabel;

  const _ReadOnlyBillSection({
    required this.billTypeLabel,
    required this.countTypeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '정산 유형',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12.0),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  countTypeLabel.isEmpty ? '-' : countTypeLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                billTypeLabel,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '정산 유형은 이 화면에서 변경할 수 없습니다.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
