import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../states/bill/bill_state.dart';
import '../../states/area/area_state.dart';

import '../../utils/firestore_logger.dart';
import 'debugs/input_debug_bottom_sheet.dart';
import 'input_plate_controller.dart';
import 'sections/input_bill_section.dart';
import 'sections/input_location_section.dart';
import 'sections/input_photo_section.dart';
import 'sections/input_plate_section.dart';
import 'sections/input_status_on_tap_section.dart';
import 'sections/input_bottom_action_section.dart';
import 'sections/input_custom_status_section.dart'; // ✅ 추가

import 'utils/input_camera_helper.dart';

import 'widgets/input_custom_status_bottom_sheet.dart';
import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'input_bottom_navigation.dart';

class InputPlateScreen extends StatefulWidget {
  const InputPlateScreen({super.key});

  @override
  State<InputPlateScreen> createState() => _InputPlateScreenState();
}

class _InputPlateScreenState extends State<InputPlateScreen> {
  final controller = InputPlateController();
  late InputCameraHelper _cameraHelper;

  List<String> selectedStatusNames = [];
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
        final data = await _fetchPlateStatus(plateNumber, area);

        if (mounted && data != null) {
          final fetchedStatus = data['customStatus'] as String?;
          final fetchedList = (data['statusList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

          setState(() {
            controller.fetchedCustomStatus = fetchedStatus;
            controller.customStatusController.text = fetchedStatus ?? '';
            selectedStatusNames = fetchedList;
            statusSectionKey = UniqueKey();
          });

          await inputCustomStatusBottomSheet(context, plateNumber, area);
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
    await FirestoreLogger().log('🔍 번호판 상태 조회 시도: $docId', level: 'called');
    final doc = await FirebaseFirestore.instance.collection('plate_status').doc(docId).get();
    if (doc.exists) {
      await FirestoreLogger().log('✅ 상태 조회 성공: $docId', level: 'success');
      return doc.data();
    }
    await FirestoreLogger().log('📭 상태 데이터 없음: $docId', level: 'info');
    return null;
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
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        title: Align(
          alignment: Alignment.centerRight,
          child: Text(
            controller.isThreeDigit ? '현재 앞자리: 세자리' : '현재 앞자리: 두자리',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              key: statusSectionKey,
              initialSelectedStatuses: selectedStatusNames,
              onSelectionChanged: (selected) {
                controller.selectedStatuses = selected;
              },
            ),
            const SizedBox(height: 32),
            InputCustomStatusSection(
              controller: controller,
              fetchedCustomStatus: controller.fetchedCustomStatus,
              selectedStatusNames: selectedStatusNames,
              statusSectionKey: statusSectionKey,
              onDeleted: () {
                setState(() {
                  controller.fetchedCustomStatus = null;
                  controller.customStatusController.clear();
                });
              },
              onStatusCleared: () {
                setState(() {
                  selectedStatusNames = [];
                  statusSectionKey = UniqueKey();
                });
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InputBottomNavigation(
            showKeypad: controller.showKeypad,
            keypad: _buildKeypad(),
            actionButton: InputBottomActionSection(
              controller: controller,
              mountedContext: mounted,
              onStateRefresh: () => setState(() {}),
            ),
          ),
          const InputDebugTriggerBar(),
        ],
      ),
    );
  }
}

class InputDebugTriggerBar extends StatelessWidget {
  const InputDebugTriggerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => const InputDebugBottomSheet(),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        color: Colors.transparent,
        child: const Icon(
          Icons.bug_report,
          size: 20,
          color: Colors.grey,
        ),
      ),
    );
  }
}
