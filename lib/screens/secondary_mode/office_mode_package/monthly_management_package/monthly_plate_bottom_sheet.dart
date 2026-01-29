// lib/screens/secondary_package/office_mode_package/monthly_management_package/monthly_plate_bottom_sheet.dart
import 'package:flutter/material.dart';

import 'monthly_plate_controller.dart';

import 'monthly_plate_payment_bottom_sheet.dart';
import 'sections/monthly_date_range_picker_section.dart';
import 'sections/monthly_plate_section.dart';
import 'sections/monthly_bottom_action_section.dart';
import 'sections/monthly_custom_status_section.dart';
import 'sections/monthly_bill_section.dart';

import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'monthly_bottom_navigation.dart';

// ✅ 결제 버튼도 동일 UI로 맞추기 위해 공용 버튼 import
import 'utils/buttons/monthly_animated_action_button.dart';

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
  Key statusSectionKey = UniqueKey();

  final TextEditingController _regularNameController = TextEditingController();
  final TextEditingController _regularAmountController = TextEditingController();
  final TextEditingController _regularDurationController = TextEditingController();
  String? _selectedRegularType;
  String _selectedPeriodUnit = '월';

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  static const String _screenTag = 'monthly setting';

  late VoidCallback _backListener;

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

    controller.isEditMode = widget.isEditMode;
    if (widget.isEditMode) {
      controller.showKeypad = false;
    }

    if (widget.isEditMode && widget.initialData != null) {
      _populateFields(widget.initialData!);
    }

    _backListener = () {
      if (controller.controllerBackDigit.text.length == 4 && controller.isInputValid()) {
        // 필요 시 후처리
      }
    };
    controller.controllerBackDigit.addListener(_backListener);
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
    controller.selectedRegularType = _selectedRegularType;

    controller.customStatusController.text = data['customStatus'] ?? '';
    controller.selectedStatuses = List<String>.from(data['statusList'] ?? []);
    controller.specialNote = data['specialNote'] ?? '';
  }

  @override
  void dispose() {
    controller.controllerBackDigit.removeListener(_backListener);

    controller.dispose();
    _regularNameController.dispose();
    _regularAmountController.dispose();
    _regularDurationController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _openPaymentSheet() async {
    FocusScope.of(context).unfocus();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => MonthlyPaymentBottomSheet(controller: controller),
    );

    if (mounted) setState(() {});
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

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: Semantics(
            label: 'screen_tag: $_screenTag',
            child: Text(_screenTag, style: style),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary.withOpacity(.18)),
            ),
            child: Icon(Icons.tune_rounded, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.isEditMode ? '정기 정산 수정' : (controller.isThreeDigit ? '현재 앞자리: 세자리' : '현재 앞자리: 두자리'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: '닫기',
            icon: Icon(Icons.close, color: cs.onSurfaceVariant),
            onPressed: () {
              final nav = Navigator.of(context, rootNavigator: true);
              if (nav.canPop()) nav.pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEntryActionArea(ColorScheme cs) {
    // ✅ 결제 버튼과 정기 정산 생성/수정 버튼을 “동일 컴포넌트”로 통일
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isEditMode) ...[
          MonthlyAnimatedActionButton(
            isLoading: false,
            enabled: !controller.isLoading,
            buttonLabel: '결제',
            leadingIcon: Icons.payments_outlined,
            onPressed: _openPaymentSheet,
          ),
          const SizedBox(height: 10),
        ],
        MonthlyBottomActionSection(
          controller: controller,
          mountedContext: mounted,
          onStateRefresh: () => setState(() {}),
          isEditMode: widget.isEditMode,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _selectedPeriodUnit = controller.selectedPeriodUnit;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = screenHeight - bottomInset;

    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: effectiveHeight,
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(.10),
                      blurRadius: 12,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildTopBar(cs),
                    const SizedBox(height: 8),
                    Container(height: 1, color: cs.outlineVariant.withOpacity(.75)),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),

                            MonthlyPlateSection(
                              dropdownValue: controller.dropdownValue,
                              regions: MonthlyPlateController.regions,
                              controllerFrontDigit: controller.controllerFrontDigit,
                              controllerMidDigit: controller.controllerMidDigit,
                              controllerBackDigit: controller.controllerBackDigit,
                              activeController: controller.activeController,
                              onKeypadStateChanged: (tc) {
                                setState(() => controller.setActiveController(tc));
                              },
                              onRegionChanged: (region) {
                                setState(() => controller.dropdownValue = region);
                              },
                              isThreeDigit: controller.isThreeDigit,
                              isEditMode: widget.isEditMode,
                            ),
                            const SizedBox(height: 32),

                            InputDecorator(
                              decoration: InputDecoration(
                                labelText: '정산 유형',
                                isDense: true,
                                filled: true,
                                fillColor: cs.surfaceVariant.withOpacity(.45),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: cs.primary, width: 1.3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text('정기', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                            ),

                            const SizedBox(height: 32),

                            MonthlyBillSection(
                              nameController: _regularNameController,
                              amountController: _regularAmountController,
                              durationController: _regularDurationController,
                              selectedType: _selectedRegularType,
                              onTypeChanged: (val) => setState(() {
                                _selectedRegularType = val;
                                controller.selectedRegularType = val;
                              }),
                              selectedPeriodUnit: _selectedPeriodUnit,
                              onPeriodUnitChanged: (val) {
                                setState(() {
                                  controller.selectedPeriodUnit = val!;
                                  _selectedPeriodUnit = val;
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
                                  statusSectionKey = UniqueKey();
                                });
                              },
                            ),

                            const SizedBox(height: 16),

                            MonthlyDateRangePickerSection(
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
                      actionButton: _buildEntryActionArea(cs),
                      backgroundColor: cs.surface,
                    ),

                    const SizedBox(height: 6),
                    Container(
                      height: 4,
                      width: 64,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),

              _buildScreenTag(context),
            ],
          ),
        ),
      ),
    );
  }
}
