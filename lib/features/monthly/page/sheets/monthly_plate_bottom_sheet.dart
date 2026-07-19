import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../controllers/monthly_plate_controller.dart';
import '../../domain/monthly_parking_options.dart';
import '../widgets/monthly_animated_action_button.dart';
import '../widgets/monthly_bottom_navigation.dart';
import '../widgets/monthly_prompt_ui.dart';
import 'monthly_plate_payment_bottom_sheet.dart';
import 'widgets/keypad/kor_keypad.dart';
import 'widgets/keypad/num_keypad.dart';
import 'widgets/monthly_bill_section.dart';
import 'widgets/monthly_bottom_action_section.dart';
import 'widgets/monthly_custom_status_section.dart';
import 'widgets/monthly_date_range_picker_section.dart';
import 'widgets/monthly_plate_section.dart';

class MonthlyPlateBottomSheet extends StatefulWidget {
  const MonthlyPlateBottomSheet({
    super.key,
    this.isEditMode = false,
    this.initialDocId,
    this.initialData,
  });

  final bool isEditMode;
  final String? initialDocId;
  final Map<String, dynamic>? initialData;

  @override
  State<MonthlyPlateBottomSheet> createState() =>
      _MonthlyPlateBottomSheetState();
}

class _MonthlyPlateBottomSheetState extends State<MonthlyPlateBottomSheet> {
  late final MonthlyPlateController controller;
  Key statusSectionKey = UniqueKey();

  final TextEditingController _regularNameController = TextEditingController();
  final TextEditingController _regularAmountController =
      TextEditingController();
  final TextEditingController _regularDurationController =
      TextEditingController();
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  String? _selectedRegularType;
  String _selectedPeriodUnit = MonthlyParkingOptions.defaultPeriodUnit(
        MonthlyParkingOptions.monthly,
      ) ??
      '월';

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
    if (widget.isEditMode) controller.showKeypad = false;
    if (widget.isEditMode && widget.initialData != null) {
      _populateFields(widget.initialData!);
    }
  }

  void _populateFields(Map<String, dynamic> data) {
    final plateParts =
        (widget.initialDocId?.split('_').first ?? '').split('-');
    if (plateParts.length == 3) {
      controller.controllerFrontDigit.text = plateParts[0];
      controller.controllerMidDigit.text = plateParts[1];
      controller.controllerBackDigit.text = plateParts[2];
      controller.isThreeDigit = plateParts[0].length == 3;
    }

    controller.dropdownValue = (data['region'] ?? '전국').toString();
    _regularNameController.text = (data['countType'] ?? '').toString();
    _regularAmountController.text = (data['regularAmount'] ?? '').toString();
    controller.paymentAmountController.text =
        (data['regularAmount'] ?? '').toString();
    _regularDurationController.text =
        (data['regularDurationValue'] ?? data['regularDurationHours'] ?? '')
            .toString();
    _startDateController.text = (data['startDate'] ?? '').toString();
    _endDateController.text = (data['endDate'] ?? '').toString();
    _selectedRegularType = MonthlyParkingOptions.normalizeRegularType(
      data['regularType']?.toString(),
    );
    _selectedPeriodUnit = MonthlyParkingOptions.resolvePeriodUnit(
      regularType: _selectedRegularType,
      periodUnit: data['periodUnit']?.toString(),
    );
    controller.selectedPeriodUnit = _selectedPeriodUnit;
    controller.selectedRegularType = _selectedRegularType;
    controller.customStatusController.text =
        (data['customStatus'] ?? '').toString();
    controller.selectedStatuses = List<String>.from(data['statusList'] ?? []);
    controller.specialNote = (data['specialNote'] ?? '').toString();
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

  Future<void> _openPaymentSheet() async {
    FocusScope.of(context).unfocus();
    await showPromptOverlayBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      transparentBackground: true,
      builder: (_) => MonthlyPaymentBottomSheet(controller: controller),
    );
    if (mounted) setState(() {});
  }

  Widget _buildKeypad() {
    final active = controller.activeController;
    if (active == controller.controllerFrontDigit) {
      return NumKeypad(
        key: const ValueKey<String>('front-keypad'),
        controller: controller.controllerFrontDigit,
        maxLength: controller.isThreeDigit ? 3 : 2,
        onComplete: () {
          setState(() {
            controller.setActiveController(controller.controllerMidDigit);
          });
        },
        onChangeFrontDigitMode: (threeDigits) {
          setState(() => controller.setFrontDigitMode(threeDigits));
        },
        enableDigitModeSwitch: true,
      );
    }
    if (active == controller.controllerMidDigit) {
      return KorKeypad(
        key: const ValueKey<String>('middle-keypad'),
        controller: controller.controllerMidDigit,
        onComplete: () {
          setState(() {
            controller.setActiveController(controller.controllerBackDigit);
          });
        },
      );
    }
    return NumKeypad(
      key: const ValueKey<String>('back-keypad'),
      controller: controller.controllerBackDigit,
      maxLength: 4,
      onComplete: () => setState(() => controller.showKeypad = false),
      onReset: () {
        setState(() {
          controller.clearInput();
          controller.setActiveController(controller.controllerFrontDigit);
        });
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
              border: Border.all(
                color: tokens.accent.withOpacity(
                  tokens.isDark ? 0.56 : 0.34,
                ),
              ),
            ),
            child: Icon(
              widget.isEditMode ? Icons.edit_note_rounded : Icons.add_road,
              color: tokens.onAccentContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isEditMode ? '정기권 수정' : '정기권 신규 등록',
                  style: textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.isEditMode
                      ? '기존 차량의 상품, 기간과 운영 메모를 수정합니다.'
                      : '차량, 상품과 기간을 차례대로 입력합니다.',
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          PromptIconButton(
            icon: Icons.close_rounded,
            tooltip: '닫기',
            haptic: PromptHaptic.selection,
            onPressed: () {
              final navigator = Navigator.of(context, rootNavigator: true);
              if (navigator.canPop()) navigator.pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementType() {
    return const MonthlyPromptSection(
      title: '정산 유형',
      subtitle: '정기 주차 등록에는 정기 정산 유형이 적용됩니다.',
      icon: Icons.confirmation_number_outlined,
      delay: Duration(milliseconds: 30),
      trailing: MonthlyPromptBadge(
        label: '고정',
        icon: Icons.lock_outline_rounded,
      ),
      child: MonthlyPromptBadge(
        label: '정기',
        icon: Icons.verified_outlined,
        tone: MonthlyPromptMessageTone.success,
      ),
    );
  }

  Widget _buildActionArea() {
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
    final reduceMotion = media.disableAnimations;
    final screenSize = media.size;
    final dialogWidth = (screenSize.width - 24).clamp(320.0, 780.0).toDouble();
    final availableHeight = screenSize.height - bottomInset - 24;
    final dialogHeight = availableHeight < 460
        ? availableHeight
        : availableHeight.clamp(460.0, 900.0).toDouble();
    final tokens = PromptUiTheme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
        child: Center(
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : PromptUiMotion.layout,
            curve: PromptUiMotion.standard,
            width: dialogWidth,
            height: dialogHeight,
            decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(PromptUiShapes.sheet),
              border: Border.all(color: tokens.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: tokens.shadow,
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: PromptAnimatedReveal(
                    child: _buildTopBar(context),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MonthlyPlateSection(
                          dropdownValue: controller.dropdownValue,
                          regions: MonthlyPlateController.regions,
                          controllerFrontDigit:
                              controller.controllerFrontDigit,
                          controllerMidDigit: controller.controllerMidDigit,
                          controllerBackDigit: controller.controllerBackDigit,
                          activeController: controller.activeController,
                          onKeypadStateChanged: (textController) {
                            setState(() {
                              controller.setActiveController(textController);
                            });
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
                          onTypeChanged: (value) {
                            setState(() {
                              controller.applyRegularType(value);
                              _selectedRegularType =
                                  controller.selectedRegularType;
                              _selectedPeriodUnit =
                                  controller.selectedPeriodUnit;
                            });
                          },
                          selectedPeriodUnit: _selectedPeriodUnit,
                          onPeriodUnitChanged: (_) {},
                          onDurationChanged: (_) {
                            setState(controller.updateEndDateFromDuration);
                          },
                          isEditMode: widget.isEditMode,
                        ),
                        const SizedBox(height: 12),
                        MonthlyDateRangePickerSection(
                          startDateController: _startDateController,
                          endDateController: _endDateController,
                          periodUnit: _selectedPeriodUnit,
                          duration:
                              int.tryParse(_regularDurationController.text) ?? 1,
                          regularType: _selectedRegularType,
                        ),
                        const SizedBox(height: 12),
                        MonthlyCustomStatusSection(
                          controller: controller,
                          fetchedCustomStatus:
                              controller.fetchedCustomStatus,
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
                  actionButton: _buildActionArea(),
                  backgroundColor: tokens.surfaceRaised,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
