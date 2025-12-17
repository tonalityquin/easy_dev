import 'package:flutter/material.dart';

import 'monthly_plate_controller.dart';

import 'sections/monthly_date_range_picker_section.dart';
import 'sections/monthly_plate_section.dart';
import 'sections/monthly_bottom_action_section.dart';
import 'sections/monthly_custom_status_section.dart';
import 'sections/monthly_bill_section.dart';

import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'monthly_bottom_navigation.dart';

class _SvcColors {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

class MonthlyPlateEntryBottomSheet extends StatefulWidget {
  final bool isEditMode;
  final String? initialDocId;
  final Map<String, dynamic>? initialData;

  const MonthlyPlateEntryBottomSheet({
    super.key,
    this.isEditMode = false,
    this.initialDocId,
    this.initialData,
  });

  @override
  State<MonthlyPlateEntryBottomSheet> createState() => _MonthlyPlateEntryBottomSheetState();
}

class _MonthlyPlateEntryBottomSheetState extends State<MonthlyPlateEntryBottomSheet> {
  late final MonthlyPlateController controller;
  Key statusSectionKey = UniqueKey();

  final TextEditingController _regularNameController = TextEditingController();
  final TextEditingController _regularAmountController = TextEditingController();
  final TextEditingController _regularDurationController = TextEditingController();
  String? _selectedRegularType;
  String _selectedPeriodUnit = '월';

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  static const String _screenTag = 'monthly entry';

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

    // 수정 모드: 키패드 기본 숨김(번호판/지역은 수정 불가이므로)
    if (widget.isEditMode) {
      controller.showKeypad = false;
    }

    // 초기 데이터 세팅
    if (widget.isEditMode && widget.initialData != null && widget.initialDocId != null) {
      controller.loadExistingData(widget.initialData!, docId: widget.initialDocId!);

      // UI 상태 동기화(드롭다운/단위 등)
      _selectedRegularType = controller.selectedRegularType;
      _selectedPeriodUnit = controller.selectedPeriodUnit;
    }

    _backListener = () {
      if (controller.controllerBackDigit.text.length == 4 && controller.isInputValid()) {
        // 필요 시 후처리
      }
    };
    controller.controllerBackDigit.addListener(_backListener);
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
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: Colors.black54,
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

  @override
  Widget build(BuildContext context) {
    // 컨트롤러 단위를 신뢰원천으로 동기화
    _selectedPeriodUnit = controller.selectedPeriodUnit;
    _selectedRegularType = controller.selectedRegularType;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = screenHeight - bottomInset;

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
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border.all(color: _SvcColors.base.withOpacity(.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.06),
                      blurRadius: 12,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 상단 바
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: _SvcColors.light.withOpacity(.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _SvcColors.light.withOpacity(.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _SvcColors.base.withOpacity(.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.edit_note_rounded, color: _SvcColors.base, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.isEditMode ? '정기 정보 수정' : '정기 정보 등록',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: '닫기',
                            icon: const Icon(Icons.close, color: _SvcColors.dark),
                            onPressed: () {
                              final nav = Navigator.of(context, rootNavigator: true);
                              if (nav.canPop()) nav.pop();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(height: 1, color: Colors.black.withOpacity(0.06)),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),

                            // 번호 입력(수정 모드: 입력/지역 버튼 비활성화 유지)
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
                                setState(() {
                                  controller.dropdownValue = region;
                                });
                              },
                              isThreeDigit: controller.isThreeDigit,
                              isEditMode: widget.isEditMode,
                            ),

                            const SizedBox(height: 24),

                            InputDecorator(
                              decoration: InputDecoration(
                                labelText: '정산 유형',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: _SvcColors.base),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('정기'),
                            ),

                            const SizedBox(height: 24),

                            // 정산 입력(수정 모드: 이름 수정 불가 적용)
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
                              isEditMode: widget.isEditMode,
                            ),

                            const SizedBox(height: 24),

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

                    // 하단 네비: (등록 모드) 키패드/버튼 토글, (수정 모드) 키패드 기본 비표시
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

                    const SizedBox(height: 6),
                    Container(
                      height: 4,
                      width: 64,
                      decoration: BoxDecoration(
                        color: _SvcColors.base.withOpacity(.18),
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
