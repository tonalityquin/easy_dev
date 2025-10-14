// lib/screens/secondary_package/office_mode_package/monthly_management_package/monthly_plate_bottom_sheet.dart
import 'package:flutter/material.dart';

import 'monthly_plate_controller.dart';

import 'sections/monthly_date_range_picker_section.dart';
import 'sections/monthly_payment_section.dart';
import 'sections/monthly_plate_section.dart';
import 'sections/monthly_bottom_action_section.dart';
import 'sections/monthly_custom_status_section.dart';
import 'sections/monthly_bill_section.dart';

import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'monthly_bottom_navigation.dart';

/// 서비스 로그인 카드와 동일 팔레트(Deep Blue)
class _SvcColors {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

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

  // 좌측 상단(11시) 라벨 텍스트
  static const String _screenTag = 'monthly setting';

  // 명시적으로 해제할 리스너 참조
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

    // 수정 모드 시 컨트롤러도 상태 반영 + 키패드 숨김
    controller.isEditMode = widget.isEditMode;
    if (widget.isEditMode) {
      controller.showKeypad = false;
    }

    // 초기 데이터 세팅
    if (widget.isEditMode && widget.initialData != null) {
      _populateFields(widget.initialData!);
    }

    // 뒤 4자리 입력 완료 감지 리스너 (필요 시 동작 추가)
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

    controller.customStatusController.text = data['customStatus'] ?? '';
    controller.selectedStatuses = List<String>.from(data['statusList'] ?? []);
  }

  @override
  void dispose() {
    // 명시적으로 리스너 제거(안전)
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

  // 11시 라벨 위젯
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
    // 컨트롤러의 단위를 신뢰원천으로 동기화
    _selectedPeriodUnit = controller.selectedPeriodUnit;

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
              // 본문
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white, // 바텀시트 배경
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
                    // 상단 상태/닫기 (토널 바)
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
                            child: const Icon(Icons.tune_rounded, color: _SvcColors.base, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              controller.isThreeDigit ? '현재 앞자리: 세자리' : '현재 앞자리: 두자리',
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

                    // 본문 스크롤 영역
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
                                // 값 초기화 없이 활성 필드 전환만
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
                            const SizedBox(height: 32),

                            // 정산 유형(단일 옵션인 경우 읽기 전용 표시가 자연스러움)
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

                            if (widget.isEditMode) ...[
                              const SizedBox(height: 16),
                              MonthlyPaymentSection(
                                controller: controller,
                                onExtendedChanged: (val) {
                                  setState(() {
                                    controller.isExtended = val ?? false;
                                  });
                                },
                              ),
                            ],

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
                                // 섹션 강제 리빌드용 키 재생성만
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
                      actionButton: MonthlyBottomActionSection(
                        controller: controller,
                        mountedContext: mounted,
                        onStateRefresh: () => setState(() {}),
                        isEditMode: widget.isEditMode,
                        // 버튼 자체는 섹션 내부에서 생성하지만 카드 팔레트에 어울리도록 기본 테마 컬러 활용
                      ),
                    ),

                    // 하단 가벼운 바
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

              // 11시 라벨(화면 좌측 상단)
              _buildScreenTag(context),
            ],
          ),
        ),
      ),
    );
  }
}
