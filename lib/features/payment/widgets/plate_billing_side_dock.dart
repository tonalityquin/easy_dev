import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/plate/domain/models/plate_model.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../applications/fee_calculator.dart';
import '../domain/models/bill_model.dart';

class BillResult {
  const BillResult({
    required this.paymentMethod,
    required this.lockedFee,
    required this.feeMode,
    required this.adjustment,
    this.reason,
  });

  final String paymentMethod;
  final int lockedFee;
  final FeeMode feeMode;
  final int adjustment;
  final String? reason;
}

typedef PlateBillingSubmit = Future<PlateModel> Function(BillResult result);
typedef PlateBillingAfterSuccess = Future<void> Function(PlateModel plate);

class PlateBillingSideDockRequest {
  const PlateBillingSideDockRequest({
    required this.plate,
    required this.source,
    required this.onSubmit,
    this.onAfterSuccess,
    this.reopenStatusAfterSuccess = true,
  });

  final PlateModel plate;
  final String source;
  final PlateBillingSubmit onSubmit;
  final PlateBillingAfterSuccess? onAfterSuccess;
  final bool reopenStatusAfterSuccess;
}

Future<PlateModel?> showPlateBillingSideDock({
  required BuildContext context,
  required PlateBillingSideDockRequest request,
}) async {
  final trace = await DeveloperOperationTrace.start(
    context: context,
    title: '차량 정산 Side Dock',
    initialMessage: '차량 정산 Side Dock을 준비합니다.',
    useCommonUi: true,
    showDialogImmediately: false,
    developerModeMessage:
        '개발자 모드 ON: 정산 동작을 추적하고 Status Dialog에서 debugPrint 코드를 복사할 수 있습니다.',
    standardModeMessage: '개발자 모드 OFF: 차량 정산 Side Dock을 실행합니다.',
  );
  trace.log(
    'plate_billing_side_dock_open presentation=operations_right_side_dock rail=none sourceDock=${request.source} targetDock=plate_billing handoffPolicy=close_then_open overlayStacking=false barrierDismissible=false motion=operations_210_190 translate=22 opacity=0.90_to_1 plate=${request.plate.plateNumber} area=${request.plate.area} billingType=${request.plate.billingType ?? '-'} billingPlanType=${request.plate.billingPlanType ?? '-'} developerMode=${trace.developerMode} debugPrint=clipboard_copy_supported',
    progress: .08,
  );

  try {
    final result = await showOperationsRightSideDock<PlateModel>(
      context: context,
      barrierLabel: '${request.plate.plateNumber} 정산',
      maxWidth: 360,
      widthFactor: .92,
      barrierDismissible: false,
      builder: (_) => PlateBillingSideDock(
        request: request,
        trace: trace,
      ),
    );
    trace.log(
      'plate_billing_side_dock_closed result=${result == null ? 'cancelled' : 'completed'} returnTarget=parking_status rail=none reopenStatus=${result == null || request.reopenStatusAfterSuccess}',
      progress: .94,
    );
    await trace.succeed(
      result == null
          ? '차량 정산 Side Dock이 취소되어 상태 처리로 복귀합니다.'
          : '차량 정산 Side Dock이 완료되었습니다.',
    );
    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }
    return result;
  } catch (error, stackTrace) {
    await trace.fail(
      '차량 정산 Side Dock 실행 중 예외가 발생했습니다.',
      error: error,
      stackTrace: stackTrace,
    );
    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }
    rethrow;
  }
}

class PlateBillingSideDock extends StatefulWidget {
  const PlateBillingSideDock({
    super.key,
    required this.request,
    required this.trace,
  });

  final PlateBillingSideDockRequest request;
  final DeveloperOperationTrace trace;

  @override
  State<PlateBillingSideDock> createState() => _PlateBillingSideDockState();
}

class _PlateBillingSideDockState extends State<PlateBillingSideDock> {
  static const List<String> _paymentOptions = <String>['계좌', '카드', '현금'];
  static const List<IconData> _paymentIcons = <IconData>[
    Icons.account_balance_rounded,
    Icons.credit_card_rounded,
    Icons.payments_rounded,
  ];
  static const List<FeeMode> _feeModes = <FeeMode>[
    FeeMode.normal,
    FeeMode.plus,
    FeeMode.minus,
  ];
  static const List<String> _feeModeLabels = <String>['일반', '할증', '할인'];
  static const List<IconData> _feeModeIcons = <IconData>[
    Icons.check_circle_outline_rounded,
    Icons.trending_up_rounded,
    Icons.trending_down_rounded,
  ];

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _reasonFocus = FocusNode();
  final GlobalKey _amountKey = GlobalKey();
  final GlobalKey _reasonKey = GlobalKey();
  final NumberFormat _currency = NumberFormat('#,###', 'ko_KR');
  final DateFormat _date = DateFormat('yyyy-MM-dd HH시 mm분');

  late final DateTime _feeSnapshotAt;
  int? _selectedPaymentIndex;
  FeeMode _feeMode = FeeMode.normal;
  int _adjustment = 0;
  String _reason = '';
  bool _saving = false;
  String? _saveError;
  int _submitCount = 0;

  PlateModel get _plate => widget.request.plate;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  String? get _selectedPayment => _selectedPaymentIndex == null
      ? null
      : _paymentOptions[_selectedPaymentIndex!];

  String get _selectedPaymentDebug => _selectedPayment ?? 'unselected';

  BillType get _billType {
    final explicitPlan = (_plate.billingPlanType ?? '').trim();
    if (explicitPlan.isNotEmpty) {
      return billTypeFromString(explicitPlan);
    }
    if ((_plate.regularAmount ?? 0) > 0) {
      return BillType.regular;
    }
    final legacyBillingType = (_plate.billingType ?? '').trim();
    if (legacyBillingType.contains('정기')) {
      return BillType.regular;
    }
    return BillType.general;
  }

  String get _billTypeResolutionSource {
    final explicitPlan = (_plate.billingPlanType ?? '').trim();
    if (explicitPlan.isNotEmpty) return 'billingPlanType';
    if ((_plate.regularAmount ?? 0) > 0) return 'legacy_regularAmount';
    if ((_plate.billingType ?? '').trim().contains('정기')) {
      return 'legacy_billingType_text';
    }
    return 'legacy_general_fallback';
  }

  bool get _isRegular => _billType == BillType.regular;

  int get _snapshotSeconds =>
      _feeSnapshotAt.toUtc().millisecondsSinceEpoch ~/ 1000;

  int get _entrySeconds =>
      _plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;

  int get _baseFee {
    if (_isRegular) return _plate.regularAmount ?? 0;
    return calculateFee(
      entryTimeInSeconds: _entrySeconds,
      currentTimeInSeconds: _snapshotSeconds,
      basicStandard: _plate.basicStandard ?? 0,
      basicAmount: _plate.basicAmount ?? 0,
      addStandard: _plate.addStandard ?? 0,
      addAmount: _plate.addAmount ?? 0,
    );
  }

  int get _finalFee => applyFeeAdjustment(
        baseFee: _baseFee,
        userAdjustment: _adjustment,
        mode: _feeMode,
      );

  bool get _submitEnabled {
    if (_saving) return false;
    if (_selectedPaymentIndex == null) return false;
    if (_feeMode == FeeMode.normal) return true;
    return _amountController.text.isNotEmpty && _reason.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _feeSnapshotAt = DateTime.now();
    _amountFocus.addListener(_handleAmountFocus);
    _reasonFocus.addListener(_handleReasonFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.trace.log(
        'plate_billing_content_mounted presentation=operations_right_side_dock rail=none formWorkflow=single_transaction payment=$_selectedPaymentDebug feeMode=${_feeMode.name} billType=${billTypeToString(_billType)} billTypeSource=$_billTypeResolutionSource billingPlanType=${_plate.billingPlanType ?? '-'} billingCountType=${_plate.billingType ?? '-'} baseFee=$_baseFee finalFee=$_finalFee snapshot=${_feeSnapshotAt.toIso8601String()} footer=fixed reduceMotion=$_reduceMotion',
        progress: .16,
      );
    });
  }

  @override
  void dispose() {
    _amountFocus.removeListener(_handleAmountFocus);
    _reasonFocus.removeListener(_handleReasonFocus);
    _amountController.dispose();
    _reasonController.dispose();
    _amountFocus.dispose();
    _reasonFocus.dispose();
    super.dispose();
  }

  void _handleAmountFocus() {
    if (_amountFocus.hasFocus) {
      _ensureVisible(_amountKey.currentContext);
    }
  }

  void _handleReasonFocus() {
    if (_reasonFocus.hasFocus) {
      _ensureVisible(_reasonKey.currentContext);
    }
  }

  void _ensureVisible(BuildContext? target) {
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: .24,
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.layout,
        curve: CommonUiMotion.enter,
      );
    });
  }

  String _formatWon(int value) => '₩${_currency.format(value)}';

  String _formatDurationMinutes(int minutes) {
    final safe = minutes < 0 ? 0 : minutes;
    final hours = safe ~/ 60;
    final rest = safe % 60;
    return '$hours시 $rest분';
  }

  String _parkedTime() {
    final minutes = ((_snapshotSeconds - _entrySeconds) / 60).ceil();
    return _formatDurationMinutes(minutes);
  }

  void _selectPayment(int index) {
    if (_saving || _selectedPaymentIndex == index) return;
    setState(() {
      _selectedPaymentIndex = index;
      _saveError = null;
    });
    HapticFeedback.selectionClick();
    widget.trace.log(
      'billing_payment_changed payment=${_paymentOptions[index]} index=$index animation=${_reduceMotion ? 'none' : 'selection'}',
      progress: .3,
    );
  }

  void _selectFeeMode(FeeMode mode) {
    if (_saving || _feeMode == mode) return;
    setState(() {
      _feeMode = mode;
      _adjustment = 0;
      _reason = '';
      _amountController.clear();
      _reasonController.clear();
      _saveError = null;
    });
    HapticFeedback.selectionClick();
    widget.trace.log(
      'billing_fee_mode_changed feeMode=${mode.name} baseFee=$_baseFee finalFee=$_finalFee adjustment=0 animation=${_reduceMotion ? 'none' : 'inline_disclosure'}',
      progress: .38,
    );
    if (mode != FeeMode.normal) {
      _ensureVisible(_amountKey.currentContext);
    }
  }

  void _updateAmount(String value) {
    final parsed = int.tryParse(value) ?? 0;
    setState(() {
      _adjustment = parsed;
      _saveError = null;
    });
    widget.trace.log(
      'billing_adjustment_changed feeMode=${_feeMode.name} adjustment=$_adjustment finalFee=$_finalFee',
      progress: .48,
    );
  }

  void _updateReason(String value) {
    setState(() {
      _reason = value.trim();
      _saveError = null;
    });
    widget.trace.log(
      'billing_reason_changed feeMode=${_feeMode.name} reasonProvided=${_reason.isNotEmpty}',
      progress: .5,
    );
  }

  Future<void> _showDeveloperStatus() async {
    if (!widget.trace.developerMode || !mounted) return;
    widget.trace.log(
      'plate_billing_status_dialog_open presentation=operations_right_side_dock rail=none sourceDock=${widget.request.source} targetDock=plate_billing handoffPolicy=close_then_open payment=$_selectedPaymentDebug feeMode=${_feeMode.name} billType=${billTypeToString(_billType)} billTypeSource=$_billTypeResolutionSource billingPlanType=${_plate.billingPlanType ?? '-'} billingCountType=${_plate.billingType ?? '-'} baseFee=$_baseFee adjustment=$_adjustment finalFee=$_finalFee saving=$_saving submitCount=$_submitCount saveError=${_saveError != null} reduceMotion=$_reduceMotion debugPrint=clipboard_copy_supported',
    );
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '차량 정산 디버그 상태',
      description: '현재 정산 흐름의 debugPrint 로그를 확인하고 클립보드로 복사할 수 있습니다.',
    );
  }

  void _cancel() {
    if (_saving) {
      widget.trace.log(
        'billing_cancel_ignored reason=saving plate=${_plate.plateNumber}',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    widget.trace.log(
      'billing_cancel_requested payment=$_selectedPaymentDebug feeMode=${_feeMode.name} adjustment=$_adjustment reasonProvided=${_reason.isNotEmpty}',
      progress: .88,
    );
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (!_submitEnabled) {
      widget.trace.log(
        'billing_submit_ignored reason=validation_or_busy saving=$_saving paymentSelected=${_selectedPaymentIndex != null} feeMode=${_feeMode.name} amountProvided=${_amountController.text.isNotEmpty} reasonProvided=${_reason.isNotEmpty}',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final result = BillResult(
      paymentMethod: _selectedPayment!,
      lockedFee: _finalFee,
      feeMode: _feeMode,
      adjustment: _adjustment,
      reason: _feeMode == FeeMode.normal ? null : _reason,
    );
    _submitCount += 1;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    HapticFeedback.mediumImpact();
    widget.trace.log(
      'billing_submit_requested submitCount=$_submitCount payment=${result.paymentMethod} feeMode=${result.feeMode.name} baseFee=$_baseFee adjustment=${result.adjustment} finalFee=${result.lockedFee} reasonProvided=${(result.reason ?? '').isNotEmpty}',
      progress: .66,
    );
    widget.trace.log(
      'billing_save_started submitCount=$_submitCount persistenceBeforeClose=true preserveInputsOnFailure=true',
      progress: .7,
    );
    try {
      final updatedPlate = await widget.request.onSubmit(result);
      if (!mounted) return;
      widget.trace.log(
        'billing_save_completed submitCount=$_submitCount plate=${updatedPlate.plateNumber} locked=${updatedPlate.isLockedFee} lockedFee=${updatedPlate.lockedFeeAmount ?? result.lockedFee} payment=${updatedPlate.paymentMethod ?? result.paymentMethod}',
        progress: .86,
      );
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(updatedPlate);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '정산을 저장하지 못했습니다. 입력 내용을 유지했습니다. 다시 시도해 주세요.';
      });
      HapticFeedback.vibrate();
      widget.trace.log(
        'billing_save_failed submitCount=$_submitCount error=$error dockPreserved=true inputPreserved=true retryAvailable=true',
        progress: .76,
      );
      widget.trace.log('billing_save_stacktrace $stackTrace');
      if (widget.trace.developerMode && mounted) {
        await widget.trace.showSnapshotStatusDialog(
          context,
          title: '정산 저장 실패',
          description: '정산 저장에 실패했습니다. 입력 내용은 유지되며 debugPrint 로그를 복사할 수 있습니다.',
          failure: true,
        );
      }
    }
  }

  List<_BillingInfoRowData> _summaryRows() {
    if (_isRegular) {
      return <_BillingInfoRowData>[
        _BillingInfoRowData(label: '정산 유형', value: billTypeToString(_billType)),
        _BillingInfoRowData(label: '정기 요금', value: _formatWon(_plate.regularAmount ?? 0)),
        if (_plate.regularDurationValue != null)
          _BillingInfoRowData(
            label: '기간값',
            value: '${_plate.regularDurationValue}',
          ),
        _BillingInfoRowData(label: '입차 시간', value: _date.format(_plate.requestTime.toLocal())),
        _BillingInfoRowData(label: '정산 기준', value: _date.format(_feeSnapshotAt.toLocal())),
        _BillingInfoRowData(label: '주차 시간', value: _parkedTime()),
      ];
    }
    return <_BillingInfoRowData>[
      _BillingInfoRowData(label: '입차 시간', value: _date.format(_plate.requestTime.toLocal())),
      _BillingInfoRowData(label: '정산 기준', value: _date.format(_feeSnapshotAt.toLocal())),
      _BillingInfoRowData(
        label: '기본 시간',
        value: _formatDurationMinutes(_plate.basicStandard ?? 0),
      ),
      _BillingInfoRowData(label: '기본 금액', value: _formatWon(_plate.basicAmount ?? 0)),
      _BillingInfoRowData(
        label: '추가 시간',
        value: _formatDurationMinutes(_plate.addStandard ?? 0),
      ),
      _BillingInfoRowData(label: '추가 금액', value: _formatWon(_plate.addAmount ?? 0)),
      _BillingInfoRowData(label: '주차 시간', value: _parkedTime()),
      _BillingInfoRowData(label: '기본 계산 금액', value: _formatWon(_baseFee)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: tokens.accentContainer,
                        borderRadius: BorderRadius.circular(CommonUiShapes.control),
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.receipt_long_rounded,
                        size: 20,
                        color: tokens.onAccentContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_plate.plateNumber} 정산',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_plate.area} · 차량 정산',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.trace.developerMode) ...[
                  const SizedBox(width: 4),
                  _BillingHeaderButton(
                    semanticLabel: '개발자 상태 보기',
                    enabled: !_saving,
                    onPressed: _showDeveloperStatus,
                    child: const Icon(Icons.bug_report_rounded, size: 18),
                  ),
                ],
                const SizedBox(width: 4),
                _BillingHeaderButton(
                  semanticLabel: '정산 취소',
                  enabled: !_saving,
                  onPressed: () async => _cancel(),
                  child: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Stack(
              children: [
                ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  children: [
                    _BillingSection(
                      title: '정산 요약',
                      child: _BillingInfoSurface(rows: _summaryRows()),
                    ),
                    const SizedBox(height: 12),
                    _BillingSection(
                      title: '결제수단',
                      child: _BillingChoiceRow(
                        children: List<Widget>.generate(
                          _paymentOptions.length,
                          (index) => _BillingChoiceButton(
                            icon: _paymentIcons[index],
                            label: _paymentOptions[index],
                            selected: _selectedPaymentIndex == index,
                            enabled: !_saving,
                            reduceMotion: _reduceMotion,
                            onPressed: () => _selectPayment(index),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _BillingSection(
                      title: '요금 적용',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _BillingChoiceRow(
                            children: List<Widget>.generate(
                              _feeModes.length,
                              (index) => _BillingChoiceButton(
                                icon: _feeModeIcons[index],
                                label: _feeModeLabels[index],
                                selected: _feeMode == _feeModes[index],
                                enabled: !_saving,
                                reduceMotion: _reduceMotion,
                                onPressed: () => _selectFeeMode(_feeModes[index]),
                              ),
                            ),
                          ),
                          AnimatedSize(
                            duration: _reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 170),
                            curve: CommonUiMotion.enter,
                            alignment: Alignment.topCenter,
                            child: AnimatedSwitcher(
                              duration: _reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 170),
                              switchInCurve: CommonUiMotion.enter,
                              switchOutCurve: CommonUiMotion.exit,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, .025),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: _feeMode == FeeMode.normal
                                  ? const SizedBox.shrink(
                                      key: ValueKey<String>('billing_normal'),
                                    )
                                  : Padding(
                                      key: ValueKey<FeeMode>(_feeMode),
                                      padding: const EdgeInsets.only(top: 10),
                                      child: _BillingAdjustmentFields(
                                        amountKey: _amountKey,
                                        reasonKey: _reasonKey,
                                        amountController: _amountController,
                                        reasonController: _reasonController,
                                        amountFocus: _amountFocus,
                                        reasonFocus: _reasonFocus,
                                        feeMode: _feeMode,
                                        enabled: !_saving,
                                        onAmountChanged: _updateAmount,
                                        onReasonChanged: _updateReason,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _BillingAmountSummary(
                      baseFee: _baseFee,
                      finalFee: _finalFee,
                      adjustment: _adjustment,
                      feeMode: _feeMode,
                      formatter: _formatWon,
                      reduceMotion: _reduceMotion,
                    ),
                    AnimatedSize(
                      duration: _reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      curve: CommonUiMotion.enter,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: _reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        child: _saveError == null
                            ? const SizedBox.shrink(
                                key: ValueKey<String>('no_save_error'),
                              )
                            : Padding(
                                key: const ValueKey<String>('save_error'),
                                padding: const EdgeInsets.only(top: 10),
                                child: _BillingErrorSurface(
                                  message: _saveError!,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                OpsDockLoadingOverlay(loading: _saving),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OpsDockContextFooter(
            children: [
              Expanded(
                child: _BillingSubmitButton(
                  enabled: _submitEnabled,
                  saving: _saving,
                  amount: _finalFee,
                  formatter: _formatWon,
                  reduceMotion: _reduceMotion,
                  onPressed: _submit,
                ),
              ),
              const SizedBox(width: 8),
              _BillingCancelButton(
                enabled: !_saving,
                onPressed: _cancel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillingHeaderButton extends StatefulWidget {
  const _BillingHeaderButton({
    required this.semanticLabel,
    required this.enabled,
    required this.onPressed,
    required this.child,
  });

  final String semanticLabel;
  final bool enabled;
  final Future<void> Function() onPressed;
  final Widget child;

  @override
  State<_BillingHeaderButton> createState() => _BillingHeaderButtonState();
}

class _BillingHeaderButtonState extends State<_BillingHeaderButton> {
  bool _pressed = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapCancel: widget.enabled ? () => _setPressed(false) : null,
        onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? .96 : 1,
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.enter,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.enabled ? tokens.surfaceRaised : tokens.surface,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(
                color: widget.enabled ? tokens.textPrimary : tokens.textDisabled,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _BillingSection extends StatelessWidget {
  const _BillingSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: textTheme.labelLarge?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _BillingInfoRowData {
  const _BillingInfoRowData({required this.label, required this.value});

  final String label;
  final String value;
}

class _BillingInfoSurface extends StatelessWidget {
  const _BillingInfoSurface({required this.rows});

  final List<_BillingInfoRowData> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      rows[index].label,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      rows[index].value,
                      textAlign: TextAlign.right,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (index != rows.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: tokens.borderSubtle,
              ),
          ],
        ],
      ),
    );
  }
}

class _BillingChoiceRow extends StatelessWidget {
  const _BillingChoiceRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 310) {
          return Row(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                Expanded(child: children[index]),
                if (index != children.length - 1) const SizedBox(width: 6),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              SizedBox(width: double.infinity, child: children[index]),
              if (index != children.length - 1) const SizedBox(height: 6),
            ],
          ],
        );
      },
    );
  }
}

class _BillingChoiceButton extends StatefulWidget {
  const _BillingChoiceButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.reduceMotion,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  State<_BillingChoiceButton> createState() => _BillingChoiceButtonState();
}

class _BillingChoiceButtonState extends State<_BillingChoiceButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final foreground = widget.selected ? tokens.accent : tokens.textPrimary;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapCancel: widget.enabled ? () => _setPressed(false) : null,
        onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? .97 : 1,
          duration: widget.reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.enter,
          child: AnimatedContainer(
            duration: widget.reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.enter,
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: widget.selected
                  ? tokens.accentContainer.withOpacity(.72)
                  : tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(
                color: widget.selected
                    ? tokens.accent.withOpacity(.5)
                    : tokens.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: widget.enabled ? foreground : tokens.textDisabled,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: widget.enabled ? foreground : tokens.textDisabled,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: widget.reduceMotion
                      ? Duration.zero
                      : CommonUiMotion.selection,
                  child: widget.selected
                      ? const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.check_rounded, size: 16),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BillingAdjustmentFields extends StatelessWidget {
  const _BillingAdjustmentFields({
    required this.amountKey,
    required this.reasonKey,
    required this.amountController,
    required this.reasonController,
    required this.amountFocus,
    required this.reasonFocus,
    required this.feeMode,
    required this.enabled,
    required this.onAmountChanged,
    required this.onReasonChanged,
  });

  final GlobalKey amountKey;
  final GlobalKey reasonKey;
  final TextEditingController amountController;
  final TextEditingController reasonController;
  final FocusNode amountFocus;
  final FocusNode reasonFocus;
  final FeeMode feeMode;
  final bool enabled;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onReasonChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final modeLabel = feeMode == FeeMode.plus ? '할증' : '할인';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$modeLabel 금액',
            style: textTheme.labelMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            key: amountKey,
            controller: amountController,
            focusNode: amountFocus,
            enabled: enabled,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: onAmountChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.payments_outlined, size: 19),
              suffixText: '원',
              filled: true,
              fillColor: tokens.canvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            '사유',
            style: textTheme.labelMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            key: reasonKey,
            controller: reasonController,
            focusNode: reasonFocus,
            enabled: enabled,
            minLines: 2,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onChanged: onReasonChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.edit_note_rounded, size: 19),
              filled: true,
              fillColor: tokens.canvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingAmountSummary extends StatelessWidget {
  const _BillingAmountSummary({
    required this.baseFee,
    required this.finalFee,
    required this.adjustment,
    required this.feeMode,
    required this.formatter,
    required this.reduceMotion,
  });

  final int baseFee;
  final int finalFee;
  final int adjustment;
  final FeeMode feeMode;
  final String Function(int value) formatter;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final detail = switch (feeMode) {
      FeeMode.normal => '기본 계산 금액',
      FeeMode.plus => '기본 ${formatter(baseFee)} + 할증 ${formatter(adjustment)}',
      FeeMode.minus => '기본 ${formatter(baseFee)} - 할인 ${formatter(adjustment)}',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.accentContainer.withOpacity(.62),
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(color: tokens.accent.withOpacity(.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '최종 정산',
                  style: textTheme.labelLarge?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            switchInCurve: CommonUiMotion.enter,
            switchOutCurve: CommonUiMotion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: .96, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              formatter(finalFee),
              key: ValueKey<int>(finalFee),
              style: textTheme.titleLarge?.copyWith(
                color: tokens.accent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingErrorSurface extends StatelessWidget {
  const _BillingErrorSurface({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.dangerContainer.withOpacity(.72),
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.danger.withOpacity(.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: tokens.danger, size: 19),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onDangerContainer,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingSubmitButton extends StatefulWidget {
  const _BillingSubmitButton({
    required this.enabled,
    required this.saving,
    required this.amount,
    required this.formatter,
    required this.reduceMotion,
    required this.onPressed,
  });

  final bool enabled;
  final bool saving;
  final int amount;
  final String Function(int value) formatter;
  final bool reduceMotion;
  final Future<void> Function() onPressed;

  @override
  State<_BillingSubmitButton> createState() => _BillingSubmitButtonState();
}

class _BillingSubmitButtonState extends State<_BillingSubmitButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.saving
          ? '정산 저장 중'
          : '${widget.formatter(widget.amount)} 정산 완료',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapCancel: widget.enabled ? () => _setPressed(false) : null,
        onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? .98 : 1,
          duration: widget.reduceMotion ? Duration.zero : CommonUiMotion.selection,
          child: AnimatedContainer(
            duration: widget.reduceMotion ? Duration.zero : CommonUiMotion.selection,
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: widget.enabled ? tokens.accent : tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(
                color: widget.enabled ? tokens.accent : tokens.borderSubtle,
              ),
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: widget.reduceMotion ? Duration.zero : CommonUiMotion.selection,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              child: widget.saving
                  ? SizedBox(
                      key: const ValueKey<String>('saving'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.3,
                        color: tokens.onAccent,
                      ),
                    )
                  : Row(
                      key: ValueKey<int>(widget.amount),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          size: 19,
                          color: widget.enabled
                              ? tokens.onAccent
                              : tokens.textDisabled,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.formatter(widget.amount)} 정산 완료',
                          style: textTheme.labelLarge?.copyWith(
                            color: widget.enabled
                                ? tokens.onAccent
                                : tokens.textDisabled,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BillingCancelButton extends StatefulWidget {
  const _BillingCancelButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_BillingCancelButton> createState() => _BillingCancelButtonState();
}

class _BillingCancelButtonState extends State<_BillingCancelButton> {
  bool _pressed = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '정산 취소',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapCancel: widget.enabled ? () => _setPressed(false) : null,
        onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? .97 : 1,
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          child: Container(
            width: 78,
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            alignment: Alignment.center,
            child: Text(
              '취소',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: widget.enabled
                        ? tokens.textPrimary
                        : tokens.textDisabled,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
