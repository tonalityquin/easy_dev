import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/bill/bill_state.dart';
import '../../states/status/status_state.dart';
import '../../states/area/area_state.dart';

import 'input_plate_controller.dart';
import 'sections/input_bill_section.dart';
import 'sections/input_location_section.dart';
import 'sections/input_photo_section.dart';
import 'sections/input_plate_section.dart';
import 'sections/input_status_on_tap_section.dart';
import 'sections/input_status_custom_section.dart';

import 'utils/input_camera_helper.dart';
import 'utils/buttons/input_animated_parking_button.dart';
import 'utils/buttons/input_animated_photo_button.dart';
import 'utils/buttons/input_animated_action_button.dart';

import 'widgets/input_location_dialog.dart';
import 'widgets/input_camera_preview_dialog.dart';
import 'widgets/input_custom_status_dialog.dart';
import 'widgets/input_bottom_navigation.dart';
import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';

class InputPlateScreen extends StatefulWidget {
  const InputPlateScreen({super.key});

  @override
  State<InputPlateScreen> createState() => _InputPlateScreenState();
}

class _InputPlateScreenState extends State<InputPlateScreen> {
  final controller = InputPlateController();
  late InputCameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = InputCameraHelper();
    _cameraHelper.initializeInputCamera().then((_) => setState(() {}));

    controller.controllerBackDigit.addListener(() async {
      final text = controller.controllerBackDigit.text;
      if (text.length == 4 && controller.isInputValid()) {
        final plateNumber = controller.buildPlateNumber();
        final area = context.read<AreaState>().currentArea;
        final customStatus = await showCustomStatusDialog(context, plateNumber, area);

        if (customStatus != null && mounted) {
          setState(() {
            controller.fetchedCustomStatus = customStatus;
          });
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final billState = context.read<BillState>();
      final statusState = context.read<StatusState>();
      final areaState = context.read<AreaState>();
      final currentArea = areaState.currentArea;

      // ✅ Firestore 호출 대신 캐시만 우선 읽기
      await billState.loadFromBillCache();
      await statusState.loadFromStatusCache(); // 캐시 우선

      final areaStatuses = statusState.statuses
          .where((status) => status.area == currentArea && status.isActive)
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
    await _cameraHelper.initializeInputCamera();

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => InputCameraPreviewDialog(
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
      builder: (_) => InputLocationDialog(
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

  VoidCallback _buildLocationAction() {
    return controller.isLocationSelected ? () => setState(() => controller.clearLocation()) : _selectParkingLocation;
  }

  Widget _buildKeypad() {
    final active = controller.activeController;

    if (active == controller.controllerFrontDigit) {
      return NumKeypad(
        controller: controller.controllerFrontDigit,
        maxLength: controller.isThreeDigit ? 3 : 2,
        onComplete: () => setState(() => controller.setActiveController(controller.controllerMidDigit)),
        onChangeFrontDigitMode: (defaultThree) {
          setState(() {
            controller.setFrontDigitMode(defaultThree);
          });
        },
        enableDigitModeSwitch: true,
      );
    }

    if (active == controller.controllerMidDigit) {
      return KorKeypad(
        controller: controller.controllerMidDigit,
        onComplete: () => setState(() => controller.setActiveController(controller.controllerBackDigit)),
      );
    }

    return NumKeypad(
      controller: controller.controllerBackDigit,
      maxLength: 4,
      onComplete: () => setState(() => controller.showKeypad = false),
      enableDigitModeSwitch: false,
      onReset: () {
        setState(() {
          controller.clearInput(); // 전체 입력 초기화
          controller.setActiveController(controller.controllerFrontDigit); // 앞자리부터 다시 시작
        });
      },
    );
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    controller.isThreeDigit ? '현재 앞자리: 세자리' : '현재 앞자리: 두자리',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InputPlateSection(
              dropdownValue: controller.dropdownValue,
              regions: controller.regions,
              controllerFrontDigit: controller.controllerFrontDigit,
              controllerMidDigit: controller.controllerMidDigit,
              controllerBackDigit: controller.controllerBackDigit,
              activeController: controller.activeController,
              onKeypadStateChanged: (_) {
                setState(() {
                  controller.clearInput();
                  controller.setActiveController(controller.controllerFrontDigit);
                });
              },
              onRegionChanged: (region) {
                setState(() {
                  controller.dropdownValue = region;
                });
              },
              isThreeDigit: controller.isThreeDigit,
            ),
            const SizedBox(height: 32),
            InputLocationSection(locationController: controller.locationController),
            const SizedBox(height: 32),
            InputPhotoSection(
              capturedImages: controller.capturedImages,
              plateNumber: controller.buildPlateNumber(),
            ),
            const SizedBox(height: 32),
            InputBillSection(
              selectedBill: controller.selectedBill,
              onChanged: (value) => setState(() => controller.selectedBill = value),
            ),
            const SizedBox(height: 32),
            InputStatusOnTapSection(
              statuses: controller.statuses,
              isSelected: controller.isSelected,
              onToggle: (index) {
                setState(() {
                  controller.toggleStatus(index);
                });
              },
            ),
            const SizedBox(height: 32),
            const Text('추가 상태 메모 (최대 10자)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: controller.customStatusController,
              maxLength: 20,
              decoration: InputDecoration(
                hintText: '예: 뒷범퍼 손상',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            if (controller.fetchedCustomStatus != null)
              InputStatusCustomSection(
                customStatus: controller.fetchedCustomStatus!,
                onDelete: () async {
                  try {
                    await controller.deleteCustomStatusFromFirestore(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('자동 메모가 삭제되었습니다')),
                    );
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('삭제 실패. 다시 시도해주세요')),
                    );
                  }
                },
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: InputBottomNavigation(
        showKeypad: controller.showKeypad,
        keypad: _buildKeypad(),
        actionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InputAnimatedPhotoButton(onPressed: _showCameraPreviewDialog),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InputAnimatedParkingButton(
                    isLocationSelected: controller.isLocationSelected,
                    onPressed: _buildLocationAction(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            InputAnimatedActionButton(
              isLoading: controller.isLoading,
              isLocationSelected: controller.isLocationSelected,
              onPressed: () => controller.handleAction(context, mounted, () => setState(() {})),
            ),
          ],
        ),
      ),
    );
  }
}
