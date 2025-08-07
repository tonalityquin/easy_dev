import 'package:flutter/material.dart';

import 'monthly_plate_controller.dart';

import 'sections/date_range_picker_section.dart';
import 'sections/monthly_payment_section.dart';
import 'sections/monthly_plate_section.dart';
import 'sections/monthly_bottom_action_section.dart';
import 'sections/monthly_custom_status_section.dart';
import 'sections/monthly_bill_section.dart';

import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'monthly_bottom_navigation.dart';

class MonthlyPlateBottomSheet extends StatefulWidget {
  final bool isEditMode;
  final String? initialDocId;
  final Map<String, dynamic>? initialData;

  const MonthlyPlateBottomSheet({
    super.key,
    this.isEditMode = false,
    this.initialDocId,
    this.initialData,
  });

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
  String _selectedPeriodUnit = '월';

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  @override
  void initState() {
    super.initState();

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

    // ✅ 수정 모드일 경우 키패드 비활성화
    if (widget.isEditMode) {
      controller.showKeypad = false;
    }

    // 초기 데이터 세팅
    if (widget.isEditMode && widget.initialData != null) {
      _populateFields(widget.initialData!);
    }

    controller.controllerBackDigit.addListener(() {
      if (controller.controllerBackDigit.text.length == 4 && controller.isInputValid()) {
        // 필요 시 동작 추가
      }
    });
  }

  void _populateFields(Map<String, dynamic> data) {
    final plateParts = (widget.initialDocId?.split('_').first ?? '').split('-');

    if (plateParts.length == 3) {
      controller.controllerFrontDigit.text = plateParts[0];
      controller.controllerMidDigit.text = plateParts[1];
      controller.controllerBackDigit.text = plateParts[2];
    }

    controller.dropdownValue = data['region'] ?? '전국';
    _regularNameController.text = data['countType'] ?? '';
    _regularAmountController.text = (data['regularAmount'] ?? '').toString();
    _regularDurationController.text = (data['regularDurationHours'] ?? '').toString();
    _startDateController.text = data['startDate'] ?? '';
    _endDateController.text = data['endDate'] ?? '';
    _selectedPeriodUnit = data['periodUnit'] ?? '월';
    _selectedRegularType = data['regularType'];
    controller.selectedPeriodUnit = _selectedPeriodUnit;
    controller.customStatusController.text = data['customStatus'] ?? '';
    controller.selectedStatuses = List<String>.from(data['statusList'] ?? []);
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
                        isEditMode: widget.isEditMode,
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
                      if (widget.isEditMode)
                        MonthlyPaymentSection(
                          controller: controller,
                          onExtendedChanged: (val) {
                            setState(() {
                              controller.isExtended = val ?? false;
                            });
                          },
                        ),
                      const SizedBox(height: 32),
                      MonthlyBillSection(
                        nameController: _regularNameController,
                        amountController: _regularAmountController,
                        durationController: _regularDurationController,
                        selectedType: _selectedRegularType,
                        onTypeChanged: (val) => setState(() => _selectedRegularType = val),
                        selectedPeriodUnit: _selectedPeriodUnit,
                        onPeriodUnitChanged: (val) {
                          setState(() {
                            _selectedPeriodUnit = val!;
                            controller.selectedPeriodUnit = val;
                          });
                        },
                      ),
                      const SizedBox(height: 32),
                      MonthlyCustomStatusSection(
                        controller: controller,
                        fetchedCustomStatus: controller.fetchedCustomStatus,
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
                        periodUnit: _selectedPeriodUnit,
                        duration: int.tryParse(_regularDurationController.text) ?? 1,
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
                  isEditMode: widget.isEditMode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
