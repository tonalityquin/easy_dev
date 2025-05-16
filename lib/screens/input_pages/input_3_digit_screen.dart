import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/keypad/num_keypad.dart';
import '../../widgets/keypad/kor_keypad.dart';
import '../../widgets/navigation/bottom_navigation.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/dialog/camera_preview_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/camera_helper.dart';
import '../../utils/button/animated_parking_button.dart';
import '../../utils/button/animated_photo_button.dart';
import '../../utils/button/animated_action_button.dart';
import 'input_plate_service.dart';
import '../../states/adjustment/adjustment_state.dart';
import '../../states/status/status_state.dart';
import '../../states/user/user_state.dart';
import '../../states/area/area_state.dart';

import 'input_plate_controller.dart';
import 'sections/adjustment_section.dart';
import 'sections/parking_location_section.dart';
import 'sections/photo_section.dart';
import 'sections/plate_input_section.dart';
import 'sections/status_chip_section.dart';

class Input3DigitScreen extends StatefulWidget {
  const Input3DigitScreen({super.key});

  @override
  State<Input3DigitScreen> createState() => _Input3DigitScreenState();
}

class _Input3DigitScreenState extends State<Input3DigitScreen> {
  final controller = InputPlateController();
  late CameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = CameraHelper();
    _cameraHelper.initializeCamera().then((_) => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final adjustmentState = context.read<AdjustmentState>();
      final statusState = context.read<StatusState>();
      final area = context.read<AreaState>().currentArea;

      adjustmentState.syncWithAreaState();

      final areaStatuses = statusState.statuses
          .where((status) => status.area == area && status.isActive)
          .map((status) => status.name)
          .toList();

      setState(() {
        controller.statuses = areaStatuses;
        controller.isSelected = List.generate(areaStatuses.length, (_) => false);
        controller.isLocationSelected = controller.locationController.text.isNotEmpty;
      });
    });
  }

  void _showCameraPreviewDialog() async {
    await _cameraHelper.initializeCamera();

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => CameraPreviewDialog(
        onImageCaptured: (image) {
          setState(() {
            controller.capturedImages.add(image);
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
      builder: (_) => ParkingLocationDialog(
        locationController: controller.locationController,
        onLocationSelected: (location) {
          setState(() {
            controller.locationController.text = location;
            controller.isLocationSelected = true;
          });
        },
      ),
    );
  }

  Future<void> _handleAction() async {
    final plateNumber = controller.buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final userName = context.read<UserState>().name;
    final adjustmentList = context.read<AdjustmentState>().adjustments;

    if (adjustmentList.isNotEmpty && controller.selectedAdjustment == null) {
      showFailedSnackbar(context, '정산 유형을 선택해주세요');
      return;
    }

    setState(() => controller.isLoading = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final uploaded = await InputPlateService.uploadCapturedImages(
        controller.capturedImages,
        plateNumber,
        area,
        userName,
      );

      final wasSuccessful = await InputPlateService.savePlateEntry(
        context: context,
        plateNumber: plateNumber,
        location: controller.locationController.text,
        isLocationSelected: controller.isLocationSelected,
        imageUrls: uploaded,
        selectedAdjustment: controller.selectedAdjustment,
        selectedStatuses: controller.selectedStatuses,
        basicStandard: controller.selectedBasicStandard,
        basicAmount: controller.selectedBasicAmount,
        addStandard: controller.selectedAddStandard,
        addAmount: controller.selectedAddAmount,
        region: controller.dropdownValue,
      );

      if (mounted) {
        Navigator.of(context).pop(); // 로딩 종료
        if (wasSuccessful) {
          showSuccessSnackbar(context, '차량 정보 등록 완료');
          setState(() => controller.resetForm());
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showFailedSnackbar(context, '등록 실패: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => controller.isLoading = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    _cameraHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('번호 등록'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlateInputSection(
              dropdownValue: controller.dropdownValue,
              regions: controller.regions,
              controller3digit: controller.controller3digit,
              controller1digit: controller.controller1digit,
              controller4digit: controller.controller4digit,
              activeController: controller.activeController,
              onKeypadStateChanged: (ctrl) {
                setState(() {
                  controller.setActiveController(ctrl);
                });
              },
              onRegionChanged: (region) {
                setState(() {
                  controller.dropdownValue = region;
                });
              },
            ),
            const SizedBox(height: 32),
            ParkingLocationSection(locationController: controller.locationController),
            const SizedBox(height: 32),
            PhotoSection(capturedImages: controller.capturedImages),
            const SizedBox(height: 32),
            AdjustmentSection(
              selectedAdjustment: controller.selectedAdjustment,
              onChanged: (value) => setState(() => controller.selectedAdjustment = value),
            ),
            const SizedBox(height: 32),
            StatusChipSection(
              statuses: controller.statuses,
              isSelected: controller.isSelected,
              onToggle: (index) {
                setState(() {
                  controller.toggleStatus(index);
                });
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigation(
        showKeypad: controller.showKeypad,
        keypad: controller.activeController == controller.controller3digit
            ? NumKeypad(
                controller: controller.controller3digit,
                maxLength: 3,
                onComplete: () => setState(() => controller.setActiveController(controller.controller1digit)),
              )
            : controller.activeController == controller.controller1digit
                ? KorKeypad(
                    controller: controller.controller1digit,
                    onComplete: () => setState(() => controller.setActiveController(controller.controller4digit)),
                  )
                : NumKeypad(
                    controller: controller.controller4digit,
                    maxLength: 4,
                    onComplete: () => setState(() => controller.showKeypad = false),
                  ),
        actionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: AnimatedPhotoButton(
                    onPressed: _showCameraPreviewDialog,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedParkingButton(
                    isLocationSelected: controller.isLocationSelected,
                    onPressed: controller.isLocationSelected
                        ? () {
                            setState(() => controller.clearLocation());
                          }
                        : _selectParkingLocation,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            AnimatedActionButton(
              isLoading: controller.isLoading,
              isLocationSelected: controller.isLocationSelected,
              onPressed: _handleAction,
            ),
          ],
        ),
      ),
    );
  }
}
