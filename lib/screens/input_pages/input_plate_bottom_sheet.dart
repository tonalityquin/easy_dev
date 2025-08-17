import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../states/bill/bill_state.dart';
import '../../states/area/area_state.dart';

import '../type_pages/debugs/firestore_logger.dart';
import 'debugs/input_debug_bottom_sheet.dart';
import 'input_plate_controller.dart';
// import 'sections/input_bill_section.dart';
import 'sections/input_location_section.dart';
import 'sections/input_photo_section.dart';
import 'sections/input_plate_section.dart';
import 'sections/input_status_on_tap_section.dart';
import 'sections/input_bottom_action_section.dart';
import 'sections/input_custom_status_section.dart';

import 'utils/input_camera_helper.dart';

import 'widgets/input_custom_status_bottom_sheet.dart';
import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'input_bottom_navigation.dart';

class InputPlateBottomSheet extends StatefulWidget {
  const InputPlateBottomSheet({super.key});

  @override
  State<InputPlateBottomSheet> createState() => _InputPlateBottomSheetState();
}

class _InputPlateBottomSheetState extends State<InputPlateBottomSheet> {
  final controller = InputPlateController();
  late InputCameraHelper _cameraHelper;

  Future<void>? _cameraInit;     // 초기화 Future 기억
  bool _cameraReady = false;     // 미리보기 렌더 가드
  bool _closing = false;         // 중복 닫기 방지

  List<String> selectedStatusNames = [];
  Key statusSectionKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _cameraHelper = InputCameraHelper();
    _cameraInit = _cameraHelper.initializeInputCamera()
        .then((_) {
      if (!mounted) return;
      setState(() => _cameraReady = true);
    })
        .catchError((_) { /* 필요 시 로깅 */ });
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

    // 🔽 초기화가 끝난 뒤 안전하게 dispose
    final init = _cameraInit;
    if (init != null) {
      init.whenComplete(() {
        try { _cameraHelper.dispose(); } catch (_) {}
      });
    } else {
      try { _cameraHelper.dispose(); } catch (_) {}
    }

    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.95,
        ),
        child: Column(
          children: [
            // 상단 제목과 닫기 버튼
            Row(
              children: [
                Expanded(
                  child: Text(
                    controller.isThreeDigit ? '현재 앞자리: 세자리' : '현재 앞자리: 두자리',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    if (_closing) return;
                    _closing = true;

                    // 🔽 미리보기를 트리에서 먼저 제거
                    if (mounted) setState(() => _cameraReady = false);

                    // 🔽 플랫폼 뷰가 실제로 내려가도록 한 프레임 대기
                    try { await WidgetsBinding.instance.endOfFrame; } catch (_) {}

                    if (mounted) Navigator.of(context).pop();
                  },
                ),

              ],
            ),
            const Divider(),

            // 본문 스크롤
            Expanded(
              child: SingleChildScrollView(
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
                    if (_cameraReady)
                      InputPhotoSection(
                        capturedImages: controller.capturedImages,
                        plateNumber: controller.buildPlateNumber(),
                      )
                    else
                      const SizedBox.shrink(),

                    const SizedBox(height: 32),
                    // InputBillSection(
                    //   selectedBill: controller.selectedBill,
                    //   onChanged: (value) => setState(() => controller.selectedBill = value),
                    //   selectedBillType: selectedBillType, // ✅ 추가
                    //   onTypeChanged: (type) => setState(() => selectedBillType = type), // ✅ 추가
                    // ),
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
                  ],
                ),
              ),
            ),

            // 하단 키패드 및 액션 버튼
            const SizedBox(height: 16),
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
