import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 기존 프로젝트 상태/섹션/위젯 import 그대로 유지
import '../../states/bill/bill_state.dart';
import '../../states/area/area_state.dart';

import 'input_plate_controller.dart';
import 'sections/input_bill_section.dart';
import 'sections/input_location_section.dart';
import 'sections/input_photo_section.dart';
import 'sections/input_plate_section.dart';
import 'sections/input_status_on_tap_section.dart';
import 'sections/input_bottom_action_section.dart';
import 'sections/input_custom_status_section.dart';

import 'widgets/input_custom_status_bottom_sheet.dart';
import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'widgets/input_bottom_navigation.dart';

// 🔽 실시간 스캐너 페이지
import 'live_ocr_page.dart';

class InputPlateScreen extends StatefulWidget {
  const InputPlateScreen({super.key});

  @override
  State<InputPlateScreen> createState() => _InputPlateScreenState();
}

class _InputPlateScreenState extends State<InputPlateScreen> {
  final controller = InputPlateController();

  List<String> selectedStatusNames = [];
  Key statusSectionKey = UniqueKey();

  String selectedBillType = '변동';

  @override
  void initState() {
    super.initState();

    controller.controllerBackDigit.addListener(() async {
      final text = controller.controllerBackDigit.text;
      if (text.length == 4 && controller.isInputValid()) {
        final plateNumber = controller.buildPlateNumber();
        final area = context.read<AreaState>().currentArea;
        final data = await _fetchPlateStatus(plateNumber, area);

        if (mounted && data != null) {
          final fetchedStatus = data['customStatus'] as String?;
          final fetchedList = (data['statusList'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
              [];

          final String? fetchedCountType =
          (data['countType'] as String?)?.trim();

          setState(() {
            controller.fetchedCustomStatus = fetchedStatus;
            controller.customStatusController.text = fetchedStatus ?? '';
            selectedStatusNames = fetchedList;
            statusSectionKey = UniqueKey();

            if (fetchedCountType != null && fetchedCountType.isNotEmpty) {
              controller.countTypeController.text = fetchedCountType;
              selectedBillType = '정기';
              controller.selectedBillType = '정기';
              controller.selectedBill = fetchedCountType;
            }
          });

          await inputCustomStatusBottomSheet(context, plateNumber, area);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final billState = context.read<BillState>();
      await billState.loadFromBillCache();
      setState(() {
        controller.isLocationSelected =
            controller.locationController.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _fetchPlateStatus(
      String plateNumber, String area) async {
    final docId = '${plateNumber}_$area';
    final doc = await FirebaseFirestore.instance
        .collection('plate_status')
        .doc(docId)
        .get();
    if (doc.exists) {
      return doc.data();
    }
    return null;
  }

  // 🔽 실시간 스캔 페이지로 이동 → 성공 시 입력칸 자동 채우기
  Future<void> _openLiveScanner() async {
    final plate = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const LiveOcrPage()),
    );
    if (plate == null) return;

    final m = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$').firstMatch(plate);
    if (m == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('인식값 형식 확인 필요: $plate')),
      );
      return;
    }

    final front = m.group(1)!; // 2 or 3 digits
    final mid = m.group(2)!;   // 한글 1글자
    final back = m.group(3)!;  // 4 digits

    setState(() {
      controller.setFrontDigitMode(front.length == 3);
      controller.controllerFrontDigit.text = front;
      controller.controllerMidDigit.text = mid;
      controller.controllerBackDigit.text = back;
      controller.showKeypad = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('인식 성공: $plate')),
    );
  }

  Widget _buildKeypad() {
    final active = controller.activeController;

    if (active == controller.controllerFrontDigit) {
      return NumKeypad(
        key: const ValueKey('frontKeypad'),
        controller: controller.controllerFrontDigit,
        maxLength: controller.isThreeDigit ? 3 : 2,
        onComplete: () => setState(
                () => controller.setActiveController(controller.controllerMidDigit)),
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
        onComplete: () => setState(
                () => controller.setActiveController(controller.controllerBackDigit)),
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
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '실시간 OCR 스캔',
            onPressed: _openLiveScanner,
            icon: const Icon(Icons.auto_awesome_motion),
          ),
        ],
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
              onChanged: (value) =>
                  setState(() => controller.selectedBill = value),
              selectedBillType: selectedBillType,
              onTypeChanged: (newType) => setState(() => selectedBillType = newType),
              countTypeController: controller.countTypeController,
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 48,
              child: Image.asset('assets/images/pelican.png'),
            ),
          ),
        ],
      ),
    );
  }
}
