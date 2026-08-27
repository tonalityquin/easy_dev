import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/plate/editor/widgets/plate_identity_input_panel.dart';
import '../../../../shared/secondary/application/secondary_monthly_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../application/monthly_date_range_calculator.dart';
import '../../domain/monthly_parking_options.dart';
import 'models/monthly_settings_draft.dart';

class MonthlyPlateSettingSectionEditorDialog extends StatefulWidget {
  const MonthlyPlateSettingSectionEditorDialog({
    super.key,
    required this.section,
    required this.initialDraft,
    required this.isEditMode,
    required this.trace,
    required this.onApply,
  });

  final MonthlyWorkspaceSection section;
  final MonthlySettingsDraft initialDraft;
  final bool isEditMode;
  final DeveloperOperationTrace trace;
  final ValueChanged<MonthlySettingsDraft> onApply;

  @override
  State<MonthlyPlateSettingSectionEditorDialog> createState() =>
      _MonthlyPlateSettingSectionEditorDialogState();
}

class _MonthlyPlateSettingSectionEditorDialogState
    extends State<MonthlyPlateSettingSectionEditorDialog> {
  static const List<String> _regions = <String>[
    '전국',
    '강원',
    '경기',
    '경남',
    '경북',
    '광주',
    '대구',
    '대전',
    '부산',
    '서울',
    '울산',
    '인천',
    '전남',
    '전북',
    '제주',
    '충남',
    '충북',
    '국기',
    '대표',
    '영사',
    '외교',
    '임시',
    '준영',
    '준외',
    '협정',
  ];

  late final TextEditingController _frontController;
  late final TextEditingController _middleController;
  late final TextEditingController _backController;
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _durationController;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _statusController;
  late final TextEditingController _noteController;
  late String _region;
  String? _regularType;
  late String _periodUnit;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _region = draft.region;
    _regularType = draft.regularType;
    _periodUnit = draft.periodUnit;
    _frontController = TextEditingController(text: draft.frontDigit);
    _middleController = TextEditingController(text: draft.middleDigit);
    _backController = TextEditingController(text: draft.backDigit);
    _nameController = TextEditingController(text: draft.countType);
    _amountController = TextEditingController(
      text: draft.regularAmount?.toString() ?? '',
    );
    _durationController = TextEditingController(
      text: draft.duration?.toString() ?? '',
    );
    _startController = TextEditingController(text: draft.startDate);
    _endController = TextEditingController(text: draft.endDate);
    _statusController = TextEditingController(text: draft.customStatus);
    _noteController = TextEditingController(text: draft.specialNote);
    widget.trace.log('편집 화면이 열렸습니다: section=${widget.section.name}');
    if (widget.section == MonthlyWorkspaceSection.vehicle &&
        !widget.isEditMode) {
      widget.trace.log(
        '차량 정보 확대 레이아웃 적용: dialog=720x660 keypad=300 segment=88 horizontalPadding=14 verticalPadding=12',
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _frontController.dispose();
    _middleController.dispose();
    _backController.dispose();
    _nameController.dispose();
    _amountController.dispose();
    _durationController.dispose();
    _startController.dispose();
    _endController.dispose();
    _statusController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _logPlateIdentity(String message) {
    widget.trace.log('monthly_plate=$message');
  }

  String get _title {
    switch (widget.section) {
      case MonthlyWorkspaceSection.vehicle:
        return '차량 정보';
      case MonthlyWorkspaceSection.product:
        return '상품과 요금';
      case MonthlyWorkspaceSection.period:
        return '정기권 기간';
      case MonthlyWorkspaceSection.memo:
        return '운영 메모';
      case MonthlyWorkspaceSection.paymentAmount:
      case MonthlyWorkspaceSection.paymentExtension:
      case MonthlyWorkspaceSection.paymentNote:
        return '정기권 설정';
    }
  }

  IconData get _icon {
    switch (widget.section) {
      case MonthlyWorkspaceSection.vehicle:
        return Icons.directions_car_rounded;
      case MonthlyWorkspaceSection.product:
        return Icons.receipt_long_rounded;
      case MonthlyWorkspaceSection.period:
        return Icons.event_available_rounded;
      case MonthlyWorkspaceSection.memo:
        return Icons.edit_note_rounded;
      case MonthlyWorkspaceSection.paymentAmount:
      case MonthlyWorkspaceSection.paymentExtension:
      case MonthlyWorkspaceSection.paymentNote:
        return Icons.local_parking_rounded;
    }
  }

  bool get _vehicleOk {
    if (widget.isEditMode) return true;
    return (_frontController.text.length == 2 ||
            _frontController.text.length == 3) &&
        _middleController.text.length == 1 &&
        _backController.text.length == 4 &&
        _region.trim().isNotEmpty;
  }

  bool get _productOk {
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    final duration = int.tryParse(_durationController.text.trim()) ?? 0;
    return _nameController.text.trim().isNotEmpty &&
        MonthlyParkingOptions.isAllowedRegularType(_regularType) &&
        MonthlyParkingOptions.isAllowedPeriodUnit(
          regularType: _regularType,
          periodUnit: _periodUnit,
        ) &&
        amount > 0 &&
        duration > 0;
  }

  String? get _periodError {
    final start = MonthlyDateRangeCalculator.parseStrict(
      _startController.text.trim(),
    );
    final end = MonthlyDateRangeCalculator.parseStrict(
      _endController.text.trim(),
    );
    final duration = int.tryParse(_durationController.text.trim()) ??
        widget.initialDraft.duration ??
        0;
    if (start == null || end == null) return '시작일과 종료일을 확인하세요.';
    if (!MonthlyParkingOptions.isAllowedRegularType(_regularType)) {
      return '상품 정보를 먼저 설정하세요.';
    }
    if (duration <= 0) return '상품 기간을 먼저 설정하세요.';
    final normalized = MonthlyDateRangeCalculator.normalizeStartDate(
      startDate: start,
      regularType: _regularType,
    );
    if (MonthlyDateRangeCalculator.format(normalized) !=
        MonthlyDateRangeCalculator.format(start)) {
      return '선택한 상품의 시작일 규칙을 확인하세요.';
    }
    final expectedEnd = MonthlyDateRangeCalculator.calculateEndDate(
      startDate: normalized,
      duration: duration,
      periodUnit: _periodUnit,
      regularType: _regularType,
    );
    if (MonthlyDateRangeCalculator.format(expectedEnd) !=
        MonthlyDateRangeCalculator.format(end)) {
      return '종료일이 상품 기간과 일치하지 않습니다.';
    }
    return null;
  }

  bool _validate() {
    switch (widget.section) {
      case MonthlyWorkspaceSection.vehicle:
        return _vehicleOk;
      case MonthlyWorkspaceSection.product:
        return _productOk;
      case MonthlyWorkspaceSection.period:
        return _periodError == null;
      case MonthlyWorkspaceSection.memo:
        return true;
      case MonthlyWorkspaceSection.paymentAmount:
      case MonthlyWorkspaceSection.paymentExtension:
      case MonthlyWorkspaceSection.paymentNote:
        return false;
    }
  }

  MonthlySettingsDraft _resultDraft() {
    final base = widget.initialDraft;
    switch (widget.section) {
      case MonthlyWorkspaceSection.vehicle:
        if (widget.isEditMode) return base;
        return base.copyWith(
          region: _region.trim(),
          frontDigit: _frontController.text.trim(),
          middleDigit: _middleController.text.trim(),
          backDigit: _backController.text.trim(),
        );
      case MonthlyWorkspaceSection.product:
        final duration = int.tryParse(_durationController.text.trim());
        final regularType = MonthlyParkingOptions.normalizeRegularType(
          _regularType,
        );
        final periodUnit = MonthlyParkingOptions.resolvePeriodUnit(
          regularType: regularType,
          periodUnit: _periodUnit,
        );
        var startDate = base.startDate;
        var endDate = base.endDate;
        final start = MonthlyDateRangeCalculator.parseStrict(startDate);
        if (start != null && duration != null && duration > 0) {
          final normalized = MonthlyDateRangeCalculator.normalizeStartDate(
            startDate: start,
            regularType: regularType,
          );
          final end = MonthlyDateRangeCalculator.calculateEndDate(
            startDate: normalized,
            duration: duration,
            periodUnit: periodUnit,
            regularType: regularType,
          );
          startDate = MonthlyDateRangeCalculator.format(normalized);
          endDate = MonthlyDateRangeCalculator.format(end);
        }
        return base.copyWith(
          countType: widget.isEditMode
              ? base.countType
              : _nameController.text.trim(),
          regularType: regularType,
          regularAmount: int.tryParse(_amountController.text.trim()),
          duration: duration,
          periodUnit: periodUnit,
          startDate: startDate,
          endDate: endDate,
        );
      case MonthlyWorkspaceSection.period:
        return base.copyWith(
          startDate: _startController.text.trim(),
          endDate: _endController.text.trim(),
        );
      case MonthlyWorkspaceSection.memo:
        return base.copyWith(
          customStatus: _statusController.text.trim(),
          specialNote: _noteController.text.trim(),
        );
      case MonthlyWorkspaceSection.paymentAmount:
      case MonthlyWorkspaceSection.paymentExtension:
      case MonthlyWorkspaceSection.paymentNote:
        return base;
    }
  }

  Future<void> _apply() async {
    setState(() => _submitted = true);
    if (!_validate()) {
      widget.trace.log('입력 검증 실패: section=${widget.section.name}');
      await HapticFeedback.mediumImpact();
      return;
    }
    final result = _resultDraft();
    widget.trace.log(
      '편집 적용: section=${widget.section.name} plateLength=${result.plateNumber.length} type=${result.regularType ?? '-'} amount=${result.regularAmount ?? 0} duration=${result.duration ?? 0}',
    );
    if (widget.section == MonthlyWorkspaceSection.vehicle &&
        !widget.isEditMode) {
      _logPlateIdentity(
        'identity_editor=monthly_apply region=${result.region} plate=${result.plateNumber}',
      );
    }
    widget.onApply(result);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  void _cancel() {
    widget.trace.log('편집 취소: section=${widget.section.name}');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log('개발자 로그 Status Dialog 요청: section=${widget.section.name}');
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '$_title 편집 로그',
      description: '현재 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  void _applyRegularType(String? value) {
    final normalized = MonthlyParkingOptions.normalizeRegularType(value);
    setState(() {
      _regularType = normalized;
      _periodUnit = MonthlyParkingOptions.resolvePeriodUnit(
        regularType: normalized,
        periodUnit: _periodUnit,
      );
    });
  }

  void _recalculateEndDate() {
    final start = MonthlyDateRangeCalculator.parseStrict(
      _startController.text.trim(),
    );
    final duration = widget.initialDraft.duration ?? 0;
    if (start == null || duration <= 0 || _regularType == null) return;
    final normalized = MonthlyDateRangeCalculator.normalizeStartDate(
      startDate: start,
      regularType: _regularType,
    );
    final end = MonthlyDateRangeCalculator.calculateEndDate(
      startDate: normalized,
      duration: duration,
      periodUnit: _periodUnit,
      regularType: _regularType,
    );
    setState(() {
      _startController.text = MonthlyDateRangeCalculator.format(normalized);
      _endController.text = MonthlyDateRangeCalculator.format(end);
    });
  }

  Widget _buildVehicle(BuildContext context) {
    if (widget.isEditMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            initialValue: widget.initialDraft.region,
            readOnly: true,
            decoration: opsInputDecoration(
              context,
              label: '번호판 지역',
              locked: true,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: widget.initialDraft.plateNumber,
            readOnly: true,
            decoration: opsInputDecoration(
              context,
              label: '차량번호',
              locked: true,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _regions.contains(_region)
              ? _region
              : '전국',
          decoration: opsInputDecoration(
            context,
            label: '번호판 지역',
            errorText: _submitted && _region.trim().isEmpty ? '지역을 선택하세요.' : null,
          ),
          items: _regions
              .map(
                (region) => DropdownMenuItem<String>(
                  value: region,
                  child: Text(region),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _region = value);
          },
        ),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          duration: widget.isEditMode || _reduceMotion
              ? Duration.zero
              : CommonUiMotion.component,
          curve: CommonUiMotion.standard,
          tween: Tween<double>(begin: 0, end: 1),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(
                scale: .98 + (.02 * value),
                alignment: Alignment.topCenter,
                child: child,
              ),
            );
          },
          child: PlateIdentityInputPanel(
            frontController: _frontController,
            middleController: _middleController,
            backController: _backController,
            initialThreeDigit: _frontController.text.trim().isEmpty
                ? true
                : _frontController.text.trim().length == 3,
            showValidationErrors: _submitted,
            onDebug: _logPlateIdentity,
            onFrontDigitModeChanged: (threeDigits) {
              _logPlateIdentity(
                'identity_editor=monthly_front_mode digits=${threeDigits ? 3 : 2}',
              );
            },
            onFocusTargetChanged: (target) {
              _logPlateIdentity(
                'identity_editor=monthly_focus target=${target.name}',
              );
            },
            keypadHeight: widget.isEditMode ? 224 : 300,
            segmentMinHeight: widget.isEditMode ? 68 : 88,
            segmentHorizontalPadding: widget.isEditMode ? 10 : 14,
            segmentVerticalPadding: widget.isEditMode ? 8 : 12,
          ),
        ),
      ],
    );
  }

  Widget _buildProduct(BuildContext context) {
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    final duration = int.tryParse(_durationController.text.trim()) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          readOnly: widget.isEditMode,
          decoration: opsInputDecoration(
            context,
            label: '정기 정산 이름',
            locked: widget.isEditMode,
            errorText: _submitted && _nameController.text.trim().isEmpty
                ? '정산 이름을 입력하세요.'
                : null,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: MonthlyParkingOptions.regularTypes.contains(_regularType)
              ? _regularType
              : null,
          decoration: opsInputDecoration(
            context,
            label: '주차 타입',
            errorText: _submitted &&
                    !MonthlyParkingOptions.isAllowedRegularType(_regularType)
                ? '주차 타입을 선택하세요.'
                : null,
          ),
          items: MonthlyParkingOptions.regularTypes
              .map(
                (type) => DropdownMenuItem<String>(
                  value: type,
                  child: Text(type),
                ),
              )
              .toList(growable: false),
          onChanged: _applyRegularType,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: opsInputDecoration(
                  context,
                  label: '기간',
                  suffixText: _periodUnit,
                  errorText: _submitted && duration <= 0 ? '1 이상' : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: opsInputDecoration(
                  context,
                  label: '정기 요금',
                  suffixText: '원',
                  errorText: _submitted && amount <= 0 ? '1원 이상' : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPeriod(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _startController,
          keyboardType: TextInputType.datetime,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
            LengthLimitingTextInputFormatter(10),
          ],
          onChanged: (_) => _recalculateEndDate(),
          decoration: opsInputDecoration(
            context,
            label: '시작일 YYYY-MM-DD',
            errorText: _submitted &&
                    MonthlyDateRangeCalculator.parseStrict(
                          _startController.text.trim(),
                        ) ==
                        null
                ? '날짜를 확인하세요.'
                : null,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _endController,
          keyboardType: TextInputType.datetime,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: opsInputDecoration(
            context,
            label: '종료일 YYYY-MM-DD',
            errorText: _submitted ? _periodError : null,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CommonButton(
              label: '오늘부터',
              variant: CommonButtonVariant.secondary,
              haptic: CommonHaptic.selection,
              onPressed: () {
                final duration = widget.initialDraft.duration ?? 0;
                final type = widget.initialDraft.regularType;
                if (duration <= 0 || type == null) return;
                final normalized = MonthlyDateRangeCalculator.normalizeStartDate(
                  startDate: DateTime.now(),
                  regularType: type,
                );
                final end = MonthlyDateRangeCalculator.calculateEndDate(
                  startDate: normalized,
                  duration: duration,
                  periodUnit: widget.initialDraft.periodUnit,
                  regularType: type,
                );
                setState(() {
                  _startController.text =
                      MonthlyDateRangeCalculator.format(normalized);
                  _endController.text = MonthlyDateRangeCalculator.format(end);
                });
              },
            ),
            CommonButton(
              label: '내일부터',
              variant: CommonButtonVariant.secondary,
              haptic: CommonHaptic.selection,
              onPressed: () {
                final duration = widget.initialDraft.duration ?? 0;
                final type = widget.initialDraft.regularType;
                if (duration <= 0 || type == null) return;
                final normalized = MonthlyDateRangeCalculator.normalizeStartDate(
                  startDate: DateTime.now().add(const Duration(days: 1)),
                  regularType: type,
                );
                final end = MonthlyDateRangeCalculator.calculateEndDate(
                  startDate: normalized,
                  duration: duration,
                  periodUnit: widget.initialDraft.periodUnit,
                  regularType: type,
                );
                setState(() {
                  _startController.text =
                      MonthlyDateRangeCalculator.format(normalized);
                  _endController.text = MonthlyDateRangeCalculator.format(end);
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMemo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _statusController,
          maxLines: 2,
          decoration: opsInputDecoration(
            context,
            label: '운영 상태',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteController,
          maxLines: 4,
          decoration: opsInputDecoration(
            context,
            label: '특이사항',
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (widget.section) {
      case MonthlyWorkspaceSection.vehicle:
        return _buildVehicle(context);
      case MonthlyWorkspaceSection.product:
        return _buildProduct(context);
      case MonthlyWorkspaceSection.period:
        return _buildPeriod(context);
      case MonthlyWorkspaceSection.memo:
        return _buildMemo(context);
      case MonthlyWorkspaceSection.paymentAmount:
      case MonthlyWorkspaceSection.paymentExtension:
      case MonthlyWorkspaceSection.paymentNote:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: tokens.surfaceRaised,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  ),
                  child: Icon(_icon, size: 20, color: tokens.onAccentContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _title,
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (widget.trace.developerMode) ...[
                  CommonIconButton(
                    icon: Icons.bug_report_outlined,
                    tooltip: '디버그 상태',
                    onPressed: _showDeveloperTrace,
                    haptic: CommonHaptic.selection,
                    size: 36,
                    iconSize: 18,
                  ),
                  const SizedBox(width: 2),
                ],
                CommonIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '닫기',
                  onPressed: _cancel,
                  haptic: CommonHaptic.light,
                  size: 36,
                  iconSize: 18,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AnimatedSwitcher(
                duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: KeyedSubtree(
                  key: ValueKey<MonthlyWorkspaceSection>(widget.section),
                  child: _buildBody(context),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: CommonButton(
                    label: '취소',
                    variant: CommonButtonVariant.secondary,
                    onPressed: _cancel,
                    haptic: CommonHaptic.selection,
                    expand: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CommonButton(
                    label: '적용',
                    icon: Icons.check_rounded,
                    onPressed: _apply,
                    haptic: CommonHaptic.medium,
                    expand: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
