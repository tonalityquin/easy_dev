import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../states/bill/bill_state.dart';
import '../../../../states/area/area_state.dart';

import '../../../type_pages/debugs/firestore_logger.dart';
import 'monthly_plate_controller.dart';

import 'sections/date_range_picker_section.dart';
import 'sections/monthly_plate_section.dart';
import 'sections/monthly_bottom_action_section.dart';
import 'sections/monthly_custom_status_section.dart';
import 'sections/monthly_bill_section.dart';

import 'widgets/monthly_custom_status_bottom_sheet.dart';
import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'monthly_bottom_navigation.dart';

class MonthlyPlateBottomSheet extends StatefulWidget {
  const MonthlyPlateBottomSheet({super.key});

  @override
  State<MonthlyPlateBottomSheet> createState() => _MonthlyPlateBottomSheetState();
}

class _MonthlyPlateBottomSheetState extends State<MonthlyPlateBottomSheet> {
  late final MonthlyPlateController controller;
  List<String> selectedStatusNames = [];
  Key statusSectionKey = UniqueKey();

  final TextEditingController _regularNameController = TextEditingController();
  final TextEditingController _regularAmountController = TextEditingController();
  final TextEditingController _regularDurationController = TextEditingController();
  String? _selectedRegularType;
  String _selectedBillingType = '정기';

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // ✅ 필드 주입 방식으로 컨트롤러 초기화
    controller = MonthlyPlateController(
      nameController: _regularNameController,
      amountController: _regularAmountController,
      durationController: _regularDurationController,
      startDateController: _startDateController,
      endDateController: _endDateController,
      regularAmountController: _regularAmountController,
      regularDurationController: _regularDurationController,
      selectedRegularType: _selectedRegularType,
    );

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

          await monthlyCustomStatusBottomSheet(context, plateNumber, area);
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
    _regularNameController.dispose();
    _regularAmountController.dispose();
    _regularDurationController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.95,
          ),
          child: Column(
            children: [
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
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MonthlyPlateSection(
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DropdownButtonFormField<String>(
                          value: _selectedBillingType,
                          decoration: const InputDecoration(
                            labelText: '정산 유형',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: '정기', child: Text('정기')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedBillingType = value!;
                              controller.selectedBillType = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 32),
                      MonthlyBillSection(
                        nameController: _regularNameController,
                        amountController: _regularAmountController,
                        durationController: _regularDurationController,
                        selectedType: _selectedRegularType,
                        onTypeChanged: (val) => setState(() => _selectedRegularType = val),
                      ),
                      const SizedBox(height: 32),
                      MonthlyCustomStatusSection(
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
                      const SizedBox(height: 16),
                      DateRangePickerSection(
                        startDateController: _startDateController,
                        endDateController: _endDateController,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              MonthlyBottomNavigation(
                showKeypad: controller.showKeypad,
                keypad: _buildKeypad(),
                actionButton: MonthlyBottomActionSection(
                  controller: controller,
                  mountedContext: mounted,
                  onStateRefresh: () => setState(() {}),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
