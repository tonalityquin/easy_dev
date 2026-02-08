import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../enums/plate_type.dart';
import '../../../models/plate_model.dart';
import '../../../utils/snackbar_helper.dart';

import 'minor_modify_plate_controller.dart';
import 'sections/minor_modify_location_section.dart';
import 'sections/minor_modify_photo_section.dart';
import 'sections/minor_modify_plate_section.dart';
import 'sections/minor_modify_status_custom_section.dart';

import 'utils/buttons/minor_modify_animated_action_button.dart';
import 'utils/buttons/minor_modify_animated_parking_button.dart';
import 'utils/buttons/minor_modify_animated_photo_button.dart';

import 'widgets/minor_modify_bottom_navigation.dart';
import 'widgets/minor_modify_camera_preview_dialog.dart';
import 'widgets/minor_modify_location_bottom_sheet.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ 로고(PNG) 가독성 보장 유틸 (수정안)
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

/// ✅ required 파라미터만 사용하는 tint 로고 위젯 (수정안)
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

    // reference 코드와 동일 기준
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

class MinorModifyPlateScreen extends StatefulWidget {
  final PlateModel plate;
  final PlateType collectionKey;

  const MinorModifyPlateScreen({
    super.key,
    required this.plate,
    required this.collectionKey,
  });

  @override
  State<MinorModifyPlateScreen> createState() => _MinorModifyPlateScreenState();
}

class _MinorModifyPlateScreenState extends State<MinorModifyPlateScreen> {
  // ⬇️ 화면 식별 태그(FAQ/에러 리포트 연계용)
  static const String screenTag = 'plate modify';

  // ✅ (수정안) 좌측 상단 태그 텍스트 대신 사용할 이미지
  static const String _kScreenTagAsset = 'assets/images/pelican_text.png';

  // ✅ (요청) 좌측 상단 태그 이미지 크기
  static const double _kScreenTagHeight = 54.0;

  // ✅ (수정안) 하단 ParkinWorkin 로고도 동일 방식 적용
  static const String _kBottomBrandAsset = 'assets/images/ParkinWorkin_text.png';
  static const double _kBottomBrandHeight = 48.0;

  late final MinorModifyPlateController _controller;

  final TextEditingController controllerFrontdigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  final List<XFile> _capturedImages = <XFile>[];
  final List<String> _existingImageUrls = <String>[];

  bool _submitting = false;
  bool _openingCameraDialog = false;

  late List<String> selectedStatusNames;

  // ───── DraggableScrollableSheet 상태/애니메이션 ─────
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  bool _sheetOpen = false; // 현재 열림 상태
  static const double _sheetClosed = 0.16; // 헤더만 보이게
  static const double _sheetOpened = 1.00; // 최상단까지(가득)

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
      // attach 전일 수 있으므로 프레임 이후 보정
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_sheetController.isAttached) return;
        _sheetController.jumpTo(target);
        if (mounted) setState(() => _sheetOpen = open);
      });
    }
  }

  void _toggleSheet() => _animateSheet(open: !_sheetOpen);

  @override
  void initState() {
    super.initState();

    _controller = MinorModifyPlateController(
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

    // ✅ 드래그로 열고/닫을 때도 _sheetOpen 동기화
    _sheetController.addListener(() {
      try {
        final s = _sheetController.size;
        final bool openNow = s >= ((_sheetClosed + _sheetOpened) / 2);
        if (mounted && openNow != _sheetOpen) {
          setState(() => _sheetOpen = openNow);
        }
      } catch (_) {
        // ignore
      }
    });
  }

  Future<void> _showCameraPreviewDialog() async {
    if (_openingCameraDialog) return;
    _openingCameraDialog = true;

    try {
      if (!mounted) return;

      // ✅ 카메라 초기화/해제는 MinorModifyCameraPreviewDialog 내부에서 책임지도록 통일
      await showDialog<void>(
        context: context,
        builder: (context) => MinorModifyCameraPreviewDialog(
          onImageCaptured: (image) {
            if (!mounted) return;
            setState(() {
              _controller.capturedImages.add(image);
            });
          },
        ),
      );

      if (!mounted) return;
      setState(() {});
    } finally {
      _openingCameraDialog = false;
    }
  }

  void _selectParkingLocation() {
    showDialog(
      context: context,
      builder: (_) => MinorModifyLocationBottomSheet(
        locationController: _controller.locationController,
        onLocationSelected: (location) {
          final trimmed = location.trim();
          if (!mounted) return;
          setState(() {
            _controller.locationController.text = trimmed;
            _controller.isLocationSelected = trimmed.isNotEmpty;
          });
        },
      ),
    );
  }

  VoidCallback _buildLocationAction() => _selectParkingLocation;

  @override
  void dispose() {
    _sheetController.dispose();
    _controller.dispose();
    controllerFrontdigit.dispose();
    controllerMidDigit.dispose();
    controllerBackDigit.dispose();
    locationController.dispose();
    super.dispose();
  }

  // ✅ (수정안) 좌측 상단(11시) 화면 태그: 텍스트 → 이미지(pelican_text.png)
  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preferred = cs.onSurfaceVariant.withOpacity(0.80);

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
                  preferredColor: preferred,
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

  // ✅ (수정안) 하단 ParkinWorkin_text 로고: 동일 방식(tint + 대비 폴백)
  Widget _buildBottomBrandLogo(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
    final sysBottom = MediaQuery.of(context).padding.bottom;

    // 본문이 하단 내비/시트와 겹치지 않도록 여유 패딩
    final bottomSafePadding = 140.0 + viewInset + sysBottom;

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
        elevation: 1,
        surfaceTintColor: Colors.transparent,

        // ✅ 좌측 상단 태그: 이미지로 교체
        flexibleSpace: _buildScreenTag(context),

        title: Text(
          '번호판 수정',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // ─── 상단 본문: 번호판 / 위치 / 사진 ───
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafePadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MinorModifyPlateSection(
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
                      MinorModifyLocationSection(
                        locationController: _controller.locationController,
                      ),
                      const SizedBox(height: 32.0),
                      MinorModifyPhotoSection(
                        capturedImages: _controller.capturedImages,
                        imageUrls: widget.plate.imageUrls ?? const <String>[],
                        plateNumber: widget.plate.plateNumber,
                      ),
                    ],
                  ),
                ),
              ),

              // ─── 하단 시트: 정산(읽기 전용) / 메모 ───
              DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: _sheetClosed,
                minChildSize: _sheetClosed,
                maxChildSize: _sheetOpened,
                snap: true,
                snapSizes: const [_sheetClosed, _sheetOpened],
                builder: (context, scrollController) {
                  final sheetBg = cs.surfaceContainerLow;

                  return Container(
                    decoration: BoxDecoration(
                      color: sheetBg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
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
                        physics: const NeverScrollableScrollPhysics(), // 요청 유지
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          16 + 100 + viewInset + sysBottom,
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
                                      color: cs.onSurface.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _sheetOpen ? '정산 / 상태 (탭하여 닫기)' : '정산 / 상태 (탭하여 열기)',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                      Text(
                                        widget.plate.plateNumber,
                                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // ✅ 정산: 사용자 수정 불가(읽기 전용)
                          _ReadOnlyBillSection(
                            billTypeLabel: _controller.selectedBillType,
                            countTypeLabel: readOnlyCountType,
                          ),

                          const SizedBox(height: 24),

                          // 추가 상태 메모
                          Text(
                            '추가 상태 메모 (최대 20자)',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _controller.customStatusController,
                            maxLength: 20,
                            decoration: InputDecoration(
                              hintText: '예: 뒷범퍼 손상',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),

                          if (_controller.fetchedCustomStatus != null)
                            MinorModifyStatusCustomSection(
                              customStatus: _controller.fetchedCustomStatus!,
                              onDelete: () async {
                                try {
                                  await _controller.deleteCustomStatusFromFirestore(context);
                                  if (!mounted) return;

                                  setState(() {
                                    _controller.fetchedCustomStatus = null;
                                    _controller.customStatusController.clear();
                                    selectedStatusNames = <String>[];
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
          MinorModifyBottomNavigation(
            actionButton: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MinorModifyAnimatedPhotoButton(
                        onPressed: _submitting ? () {} : _showCameraPreviewDialog,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MinorModifyAnimatedParkingButton(
                        isLocationSelected: _controller.isLocationSelected,
                        onPressed: _submitting ? () {} : _buildLocationAction(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                MinorModifyAnimatedActionButton(
                  isLoading: _submitting,
                  isLocationSelected: _controller.isLocationSelected,
                  buttonLabel: '수정 완료',
                  onPressed: () async {
                    if (_submitting) return;
                    setState(() => _submitting = true);

                    try {
                      await _controller.handleAction(() {
                        if (!mounted) return;
                        Navigator.pop(context);
                        showSuccessSnackbar(context, '수정이 완료되었습니다!');
                      }, selectedStatusNames);
                    } finally {
                      if (mounted) setState(() => _submitting = false);
                    }
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
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '정산 유형',
          style: text.titleMedium?.copyWith(
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
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  countTypeLabel.trim().isEmpty ? '-' : countTypeLabel.trim(),
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                billTypeLabel.trim().isEmpty ? '-' : billTypeLabel.trim(),
                style: text.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '정산 유형은 이 화면에서 변경할 수 없습니다.',
          style: text.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
