import 'package:flutter/material.dart';

import '../../controllers/monthly_plate_controller.dart';
import '../widgets/monthly_animated_action_button.dart';
import '../widgets/monthly_bottom_navigation.dart';
import 'monthly_plate_payment_bottom_sheet.dart';
import 'widgets/keypad/kor_keypad.dart';
import 'widgets/keypad/num_keypad.dart';
import 'widgets/monthly_bill_section.dart';
import 'widgets/monthly_bottom_action_section.dart';
import 'widgets/monthly_custom_status_section.dart';
import 'widgets/monthly_date_range_picker_section.dart';
import 'widgets/monthly_plate_section.dart';

const _editorInk = Color(0xFF101828);
const _editorMuted = Color(0xFF667085);
const _editorCanvas = Color(0xFFF3F6FA);
const _editorPanel = Color(0xFFFFFFFF);
const _editorLine = Color(0xFFD8DEE8);
const _editorBlue = Color(0xFF2563EB);

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
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  String? _selectedRegularType;
  String _selectedPeriodUnit = '월';
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
      if (controller.controllerBackDigit.text.length == 4 && controller.isInputValid()) {}
    };
    controller.controllerBackDigit.addListener(_backListener);
  }

  void _populateFields(Map<String, dynamic> data) {
    final plateParts = (widget.initialDocId?.split('_').first ?? '').split('-');

    if (plateParts.length == 3) {
      controller.controllerFrontDigit.text = plateParts[0];
      controller.controllerMidDigit.text = plateParts[1];
      controller.controllerBackDigit.text = plateParts[2];
      controller.isThreeDigit = plateParts[0].length == 3;
    }

    controller.dropdownValue = (data['region'] ?? '전국').toString();
    _regularNameController.text = (data['countType'] ?? '').toString();
    _regularAmountController.text = (data['regularAmount'] ?? '').toString();
    _regularDurationController.text = (data['regularDurationHours'] ?? '').toString();
    _startDateController.text = (data['startDate'] ?? '').toString();
    _endDateController.text = (data['endDate'] ?? '').toString();

    _selectedPeriodUnit = (data['periodUnit'] ?? '월').toString();
    _selectedRegularType = data['regularType']?.toString();
    controller.selectedPeriodUnit = _selectedPeriodUnit;
    controller.selectedRegularType = _selectedRegularType;
    controller.customStatusController.text = (data['customStatus'] ?? '').toString();
    controller.selectedStatuses = List<String>.from(data['statusList'] ?? []);
    controller.specialNote = (data['specialNote'] ?? '').toString();
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
    await showModalBottomSheet<void>(
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
          setState(() => controller.setFrontDigitMode(defaultThree));
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

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _editorInk,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _editorBlue,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(widget.isEditMode ? Icons.edit_note : Icons.add_road, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isEditMode ? '정기권 수정' : '정기권 신규 등록',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.isEditMode ? '차량번호와 지점은 잠겨 있습니다.' : '차량, 상품, 기간을 순서대로 입력하세요.',
                  style: const TextStyle(
                    color: Color(0xFFB8C2D6),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: () {
              final nav = Navigator.of(context, rootNavigator: true);
              if (nav.canPop()) nav.pop();
            },
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementType() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _editorPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _editorLine),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.confirmation_number_outlined, color: _editorBlue, size: 19),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '정산 유형',
                  style: TextStyle(color: _editorMuted, fontWeight: FontWeight.w800, fontSize: 12),
                ),
                SizedBox(height: 2),
                Text(
                  '정기',
                  style: TextStyle(color: _editorInk, fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _editorLine),
            ),
            child: const Text(
              '고정',
              style: TextStyle(color: _editorMuted, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryActionArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isEditMode) ...[
          MonthlyAnimatedActionButton(
            isLoading: false,
            enabled: !controller.isLoading,
            buttonLabel: '결제 화면 열기',
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
    _selectedRegularType = controller.selectedRegularType;

    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final screenSize = media.size;
    var dialogWidth = screenSize.width - 24;
    if (dialogWidth > 780) dialogWidth = 780;
    var dialogHeight = screenSize.height - bottomInset - 28;
    if (dialogHeight > 900) dialogHeight = 900;
    if (dialogHeight < 460) dialogHeight = screenSize.height - bottomInset - 12;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: bottomInset + 12),
        child: Center(
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: _editorCanvas,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _editorLine),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.18),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: _buildTopBar(),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                            const SizedBox(height: 12),
                            _buildSettlementType(),
                            const SizedBox(height: 12),
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
                                if (val == null) return;
                                setState(() {
                                  controller.selectedPeriodUnit = val;
                                  _selectedPeriodUnit = val;
                                  controller.updateEndDateFromDuration();
                                });
                              },
                              onDurationChanged: (_) {
                                setState(() {
                                  controller.updateEndDateFromDuration();
                                });
                              },
                              isEditMode: widget.isEditMode,
                            ),
                            const SizedBox(height: 12),
                            MonthlyDateRangePickerSection(
                              startDateController: _startDateController,
                              endDateController: _endDateController,
                              periodUnit: _selectedPeriodUnit,
                              duration: int.tryParse(_regularDurationController.text) ?? 1,
                            ),
                            const SizedBox(height: 12),
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
                                setState(() => statusSectionKey = UniqueKey());
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    MonthlyBottomNavigation(
                      showKeypad: controller.showKeypad,
                      keypad: _buildKeypad(),
                      actionButton: _buildEntryActionArea(),
                      backgroundColor: _editorPanel,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
