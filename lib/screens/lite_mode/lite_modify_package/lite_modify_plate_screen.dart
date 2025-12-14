import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../../models/plate_model.dart';
import '../../../enums/plate_type.dart';

import 'lite_modify_plate_controller.dart';
import 'sections/lite_modify_bill_section.dart';
import 'sections/lite_modify_location_section.dart';
import 'sections/lite_modify_photo_section.dart';
import 'sections/lite_modify_plate_section.dart';
import 'sections/lite_modify_status_custom_section.dart';

import 'utils/buttons/lite_modify_animated_action_button.dart';
import 'utils/buttons/lite_modify_animated_parking_button.dart';
import 'utils/buttons/lite_modify_animated_photo_button.dart';

import 'widgets/lite_modify_bottom_navigation.dart';
import 'widgets/lite_modify_camera_preview_dialog.dart';
import 'widgets/lite_modify_location_bottom_sheet.dart';
import '../../../utils/snackbar_helper.dart';
import 'utils/lite_modify_camera_helper.dart';

class LiteModifyPlateScreen extends StatefulWidget {
  final PlateModel plate;
  final PlateType collectionKey;

  const LiteModifyPlateScreen({
    super.key,
    required this.plate,
    required this.collectionKey,
  });

  @override
  State<LiteModifyPlateScreen> createState() => _LiteModifyPlateScreenState();
}

class _LiteModifyPlateScreenState extends State<LiteModifyPlateScreen> {
  // ⬇️ 화면 식별 태그(FAQ/에러 리포트 연계용)
  static const String screenTag = 'plate modify';

  late LiteModifyPlateController _controller;
  late LiteModifyCameraHelper _cameraHelper;

  final TextEditingController controllerFrontdigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  final List<XFile> _capturedImages = [];
  final List<String> _existingImageUrls = [];

  bool isLoading = false;
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

    _controller = LiteModifyPlateController(
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

    _cameraHelper = LiteModifyCameraHelper();
    _cameraHelper.initializeInputCamera().then((_) => setState(() {}));

    _controller.initializePlate();
    _controller.initializeFieldValues();

    selectedStatusNames = List<String>.from(widget.plate.statusList);
  }

  void _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => LiteModifyCameraPreviewDialog(
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
      builder: (_) => LiteModifyLocationBottomSheet(
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

  // 좌측 상단(11시) 화면 태그 위젯
  Widget _buildScreenTag(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer( // 제스처 간섭 방지
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: $screenTag',
              child: Text(screenTag, style: style),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    // 본문이 하단 내비/시트와 겹치지 않도록 여유 패딩
    final bottomSafePadding = 140.0 + viewInset;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // ⬅️ 뒤로가기 화살표 제거
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        // ⬇️ 좌측 상단(11시)에 'plate modify' 텍스트 고정
        flexibleSpace: _buildScreenTag(context),
        title: const Text(
          "번호판 수정",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // ─── 상단 본문: 번호판 / 위치 / 사진 (작은 폰 보완: 스크롤 허용) ───
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafePadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LiteModifyPlateSection(
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
                      LiteModifyLocationSection(locationController: _controller.locationController),
                      const SizedBox(height: 32.0),
                      LiteModifyPhotoSection(
                        capturedImages: _controller.capturedImages,
                        imageUrls: widget.plate.imageUrls ?? [],
                        plateNumber: widget.plate.plateNumber,
                      ),
                    ],
                  ),
                ),
              ),

              // ─── 하단 시트: 정산 / 상태(토글) / 메모 ───
              DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: _sheetClosed,
                minChildSize: _sheetClosed,
                maxChildSize: _sheetOpened, // 최상단까지
                snap: true,
                snapSizes: const [_sheetClosed, _sheetOpened],
                builder: (context, scrollController) {
                  // 메인 배경과 미세하게 구분되는 옅은 톤
                  const sheetBg = Color(0xFFF6F8FF);

                  return Container(
                    decoration: const BoxDecoration(
                      color: sheetBg,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -4)),
                      ],
                    ),
                    child: SafeArea(
                      top: true,
                      bottom: false,
                      child: ListView(
                        controller: scrollController,
                        physics: const NeverScrollableScrollPhysics(), // 내부 스크롤 금지(요청 유지)
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          16 + 100 + viewInset, // 하단 내비와 겹치지 않도록 여유
                        ),
                        children: [
                          // 헤더(탭으로 열고/닫기 + 애니메이션)
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
                                      color: Colors.black38,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _sheetOpen ? '정산 / 상태 (탭하여 닫기)' : '정산 / 상태 (탭하여 열기)',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                      ),
                                      Text(
                                        widget.plate.plateNumber,
                                        style: const TextStyle(color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 정산
                          LiteModifyBillSection(
                            selectedBill: _controller.selectedBillCountType,
                            selectedBillType: _controller.selectedBillType,
                            onChanged: (bill) {
                              setState(() {
                                _controller.applyBillDefaults(bill);
                              });
                            },
                            onTypeChanged: (type) {
                              setState(() {
                                _controller.onBillTypeChanged(type);
                              });
                            },
                          ),

                          const SizedBox(height: 24),

                          // 추가 상태 메모
                          const Text(
                            '추가 상태 메모 (최대 20자)',
                            style: TextStyle(fontWeight: FontWeight.bold),
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
                            LiteModifyStatusCustomSection(
                              customStatus: _controller.fetchedCustomStatus!,
                              onDelete: () async {
                                try {
                                  await _controller.deleteCustomStatusFromFirestore(context);
                                  setState(() {
                                    _controller.fetchedCustomStatus = null;
                                    _controller.customStatusController.clear();
                                    selectedStatusNames = [];
                                  });
                                  showSuccessSnackbar(context, '자동 메모가 삭제되었습니다');
                                } catch (_) {
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
          LiteModifyBottomNavigation(
            actionButton: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LiteModifyAnimatedPhotoButton(onPressed: _showCameraPreviewDialog),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LiteModifyAnimatedParkingButton(
                        isLocationSelected: _controller.isLocationSelected,
                        onPressed: _buildLocationAction(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                LiteModifyAnimatedActionButton(
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 48,
                child: Image.asset('assets/images/pelican.png'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
