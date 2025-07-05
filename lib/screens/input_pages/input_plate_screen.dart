import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../states/bill/bill_state.dart';
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
import 'widgets/input_bottom_navigation.dart';
import 'widgets/input_custom_status_dialog.dart';
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

  /// 선택된 상태들
  List<String> selectedStatusNames = [];

  /// 상태 선택 섹션 Key (토글 상태를 새로 그리기 위해)
  Key statusSectionKey = UniqueKey();

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

        // Firestore에서 상태와 메모 불러오기
        final data = await _fetchPlateStatus(plateNumber, area);

        if (mounted && data != null) {
          final fetchedStatus = data['customStatus'] as String?;
          final fetchedList = (data['statusList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

          setState(() {
            controller.fetchedCustomStatus = fetchedStatus;
            controller.customStatusController.text = fetchedStatus ?? '';
            selectedStatusNames = fetchedList;
            statusSectionKey = UniqueKey(); // ✅ 강제 리빌드
          });

          // 다이얼로그 띄우기
          await showInputCustomStatusDialog(context, plateNumber, area);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final billState = context.read<BillState>();
      await billState.loadFromBillCache();
      setState(() {
        controller.isLocationSelected = controller.locationController.text.isNotEmpty;
      });
    });
  }

  Future<Map<String, dynamic>?> _fetchPlateStatus(String plateNumber, String area) async {
    final docId = '${plateNumber}_$area';
    final doc = await FirebaseFirestore.instance.collection('plate_status').doc(docId).get();
    if (doc.exists) {
      return doc.data();
    }
    return null;
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
        key: const ValueKey('frontKeypad'),
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
        key: const ValueKey('midKeypad'),
        controller: controller.controllerMidDigit,
        onComplete: () => setState(() => controller.setActiveController(controller.controllerBackDigit)),
      );
    }

    return NumKeypad(
      key: const ValueKey('backKeypad'),
      controller: controller.controllerBackDigit,
      maxLength: 4,
      onComplete: () => setState(() => controller.showKeypad = false),
      enableDigitModeSwitch: false,
      onReset: () {
        setState(() {
          controller.clearInput();
          controller.setActiveController(controller.controllerFrontDigit);
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
              key: statusSectionKey, // ✅ 강제 리빌드를 위해 Key 부여
              initialSelectedStatuses: selectedStatusNames,
              onSelectionChanged: (selected) {
                controller.selectedStatuses = selected;
              },
            ),
            const SizedBox(height: 32),
            const Text(
              '추가 상태 메모 (최대 10자)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
                    setState(() {
                      controller.fetchedCustomStatus = null;
                      controller.customStatusController.clear();
                      selectedStatusNames = [];
                      statusSectionKey = UniqueKey();
                    });
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
              onPressed: () => controller.submitPlateEntry(context, mounted, () => setState(() {})),
            ),
          ],
        ),
      ),
    );
  }
}
