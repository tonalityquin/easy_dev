import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../applications/fee_calculator.dart';

class BillResult {
  final String paymentMethod;
  final int lockedFee;
  final FeeMode feeMode;
  final int adjustment;
  final String? reason;

  BillResult({
    required this.paymentMethod,
    required this.lockedFee,
    required this.feeMode,
    required this.adjustment,
    this.reason,
  });
}

Future<BillResult?> showOnTapBillingBottomSheet({
  required BuildContext context,
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard,
  required int basicAmount,
  required int addStandard,
  required int addAmount,
  required String billingType,
  int? regularAmount,
  int? regularDurationHours,
  int? regularDurationValue,
  void Function(String message)? traceLog,
}) async {
  void trace(String message) {
    final line = 'billing_sheet=$message';
    if (traceLog != null) {
      traceLog(line);
      return;
    }
    debugPrint(line);
  }

  trace(
    'open billingType=${billingType.trim().isEmpty ? "unknown" : billingType.trim()} '
    'entry=$entryTimeInSeconds current=$currentTimeInSeconds',
  );

  final result = await showCommonOverlayBottomSheet<BillResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    transparentBackground: true,
    builder: (_) => BillingBottomSheet(
      entryTimeInSeconds: entryTimeInSeconds,
      currentTimeInSeconds: currentTimeInSeconds,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
      billingType: billingType,
      regularAmount: regularAmount,
      regularDurationValue: regularDurationValue ?? regularDurationHours,
      traceLog: trace,
    ),
  );

  if (result == null) {
    trace('closed result=cancelled');
  } else {
    trace(
      'closed result=completed payment=${result.paymentMethod} '
      'mode=${result.feeMode.name} amount=${result.lockedFee} adjustment=${result.adjustment}',
    );
  }
  return result;
}

class BillingBottomSheet extends StatefulWidget {
  final int entryTimeInSeconds;
  final int currentTimeInSeconds;
  final int basicStandard;
  final int basicAmount;
  final int addStandard;
  final int addAmount;
  final String billingType;
  final int? regularAmount;
  final int? regularDurationValue;
  final void Function(String message)? traceLog;

  const BillingBottomSheet({
    super.key,
    required this.entryTimeInSeconds,
    required this.currentTimeInSeconds,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
    required this.billingType,
    this.regularAmount,
    int? regularDurationHours,
    int? regularDurationValue,
    this.traceLog,
  }) : regularDurationValue = regularDurationValue ?? regularDurationHours;

  @override
  State<BillingBottomSheet> createState() => _BillingBottomSheetState();
}

class _BillingBottomSheetState extends State<BillingBottomSheet> {
  final List<String> paymentOptions = const ['계좌', '카드', '현금'];
  final List<IconData> paymentIcons = const [
    Icons.account_balance_rounded,
    Icons.credit_card_rounded,
    Icons.payments_rounded,
  ];
  final List<String> modeLabels = const ['일반', '할증', '할인'];
  final List<IconData> modeIcons = const [
    Icons.check_circle_outline_rounded,
    Icons.trending_up_rounded,
    Icons.trending_down_rounded,
  ];

  int _selectedPaymentIndex = 0;
  FeeMode _feeMode = FeeMode.normal;
  int _userAdjustment = 0;
  String? _inputReason;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  final FocusNode _amountFocus = FocusNode();
  final FocusNode _reasonFocus = FocusNode();
  final GlobalKey _amountKey = GlobalKey();
  final GlobalKey _reasonKey = GlobalKey();

  final formatCurrency = NumberFormat('#,###', 'ko_KR');
  final formatDate = DateFormat('yyyy-MM-dd HH시 mm분');

  String get _selectedPayment => paymentOptions[_selectedPaymentIndex];

  BillType get billType => billTypeFromString(widget.billingType);

  bool get isRegular => billType == BillType.fixed;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _trace(String message) {
    final callback = widget.traceLog;
    if (callback != null) {
      callback(message);
      return;
    }
    debugPrint('billing_sheet=$message');
  }

  @override
  void initState() {
    super.initState();
    _amountFocus.addListener(() {
      if (_amountFocus.hasFocus) _ensureVisible(_amountKey.currentContext);
    });
    _reasonFocus.addListener(() {
      if (_reasonFocus.hasFocus) _ensureVisible(_reasonKey.currentContext);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    _amountFocus.dispose();
    _reasonFocus.dispose();
    super.dispose();
  }

  void _ensureVisible(BuildContext? target) {
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.25,
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.layout,
        curve: Curves.easeOut,
      );
    });
  }

  int _calculateBaseFee() {
    if (isRegular) return widget.regularAmount ?? 0;
    return calculateFee(
      entryTimeInSeconds: widget.entryTimeInSeconds,
      currentTimeInSeconds: widget.currentTimeInSeconds,
      basicStandard: widget.basicStandard,
      basicAmount: widget.basicAmount,
      addStandard: widget.addStandard,
      addAmount: widget.addAmount,
      userAdjustment: 0,
      mode: FeeMode.normal,
    );
  }

  int _getLockedFee() {
    return calculateFee(
      entryTimeInSeconds: widget.entryTimeInSeconds,
      currentTimeInSeconds: widget.currentTimeInSeconds,
      basicStandard: widget.basicStandard,
      basicAmount: widget.basicAmount,
      addStandard: widget.addStandard,
      addAmount: widget.addAmount,
      userAdjustment: _userAdjustment,
      mode: _feeMode,
      billingType: widget.billingType,
      regularAmount: widget.regularAmount,
    );
  }

  String _formatMinutesToHourMinute(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '$hours시 $minutes분';
  }

  String _getFormattedParkedTime() {
    final totalMinutes =
        ((widget.currentTimeInSeconds - widget.entryTimeInSeconds) / 60).ceil();
    return _formatMinutesToHourMinute(totalMinutes);
  }

  String _getFormattedEntryTime() {
    final entry =
        DateTime.fromMillisecondsSinceEpoch(widget.entryTimeInSeconds * 1000);
    return formatDate.format(entry);
  }

  bool get _isSubmitEnabled {
    if (_feeMode == FeeMode.normal) return true;
    return _amountController.text.isNotEmpty &&
        _reasonController.text.trim().isNotEmpty;
  }

  void _selectPayment(int index) {
    if (_selectedPaymentIndex == index) return;
    setState(() => _selectedPaymentIndex = index);
    _trace('selection payment=${paymentOptions[index]}');
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  void _selectFeeMode(FeeMode mode) {
    if (_feeMode == mode) return;
    setState(() {
      _feeMode = mode;
      _userAdjustment = 0;
      _inputReason = null;
      _amountController.clear();
      _reasonController.clear();
    });
    _trace('selection feeMode=${mode.name}');
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
    if (mode != FeeMode.normal) {
      _ensureVisible(_amountKey.currentContext);
    }
  }

  void _submit(int lockedFee) {
    if (!_isSubmitEnabled) return;
    FocusScope.of(context).unfocus();
    _trace(
      'submit payment=$_selectedPayment mode=${_feeMode.name} '
      'amount=$lockedFee adjustment=$_userAdjustment reasonProvided=${(_inputReason ?? '').isNotEmpty}',
    );
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    Navigator.of(context).pop(
      BillResult(
        paymentMethod: _selectedPayment,
        lockedFee: lockedFee,
        feeMode: _feeMode,
        adjustment: _userAdjustment,
        reason: _feeMode == FeeMode.normal ? null : _inputReason,
      ),
    );
  }

  void _cancel() {
    FocusScope.of(context).unfocus();
    _trace('cancel action=user_cancel');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final baseFee = _calculateBaseFee();
    final lockedFee = _getLockedFee();

    return SafeArea(
      child: Material(
        color: tokens.transparent,
        child: AnimatedPadding(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: DraggableScrollableSheet(
            initialChildSize: 0.88,
            minChildSize: 0.54,
            maxChildSize: 0.96,
            builder: (_, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(CommonUiShapes.sheet),
                  ),
                  border: Border.all(color: tokens.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.shadow,
                      blurRadius: 24,
                      offset: const Offset(0, -7),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                        children: [
                          _BillingReveal(
                            order: 0,
                            child: _BillingHeader(
                              onClose: _cancel,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _BillingReveal(
                            order: 1,
                            child: _BillingSection(
                              title: '정산 정보',
                              subtitle: '현재 차량의 요금 기준과 주차 시간을 확인합니다.',
                              child: _BillingInfoCard(
                                rows: isRegular
                                    ? [
                                        _BillingInfoRowData(
                                          label: '고정 유형',
                                          value: widget.billingType,
                                        ),
                                        if (widget.regularAmount != null)
                                          _BillingInfoRowData(
                                            label: '고정 요금',
                                            value:
                                                '₩${formatCurrency.format(widget.regularAmount)}',
                                          ),
                                        if (widget.regularDurationValue != null)
                                          _BillingInfoRowData(
                                            label: '기간값',
                                            value:
                                                '${widget.regularDurationValue}',
                                          ),
                                        _BillingInfoRowData(
                                          label: '입차 시간',
                                          value: _getFormattedEntryTime(),
                                        ),
                                        _BillingInfoRowData(
                                          label: '주차 시간',
                                          value: _getFormattedParkedTime(),
                                        ),
                                      ]
                                    : [
                                        _BillingInfoRowData(
                                          label: '입차 시간',
                                          value: _getFormattedEntryTime(),
                                        ),
                                        _BillingInfoRowData(
                                          label: '기본 시간',
                                          value: _formatMinutesToHourMinute(
                                            widget.basicStandard,
                                          ),
                                        ),
                                        _BillingInfoRowData(
                                          label: '기본 금액',
                                          value:
                                              '₩${formatCurrency.format(widget.basicAmount)}',
                                        ),
                                        _BillingInfoRowData(
                                          label: '추가 시간',
                                          value: _formatMinutesToHourMinute(
                                            widget.addStandard,
                                          ),
                                        ),
                                        _BillingInfoRowData(
                                          label: '추가 금액',
                                          value:
                                              '₩${formatCurrency.format(widget.addAmount)}',
                                        ),
                                        _BillingInfoRowData(
                                          label: '주차 시간',
                                          value: _getFormattedParkedTime(),
                                        ),
                                        _BillingInfoRowData(
                                          label: '기본 계산 금액',
                                          value:
                                              '₩${formatCurrency.format(baseFee)}',
                                        ),
                                      ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _BillingReveal(
                            order: 2,
                            child: _BillingSection(
                              title: '지불 방법',
                              subtitle: '정산에 기록할 지불 방법을 선택합니다.',
                              child: _BillingChoiceGrid(
                                itemCount: paymentOptions.length,
                                itemBuilder: (context, index) {
                                  return _BillingChoiceCard(
                                    icon: paymentIcons[index],
                                    title: paymentOptions[index],
                                    selected:
                                        _selectedPaymentIndex == index,
                                    onPressed: () => _selectPayment(index),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _BillingReveal(
                            order: 3,
                            child: _BillingSection(
                              title: '요금 모드',
                              subtitle: '일반 요금 또는 할증·할인을 선택합니다.',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _BillingChoiceGrid(
                                    itemCount: FeeMode.values.length,
                                    itemBuilder: (context, index) {
                                      final mode = FeeMode.values[index];
                                      return _BillingChoiceCard(
                                        icon: modeIcons[index],
                                        title: modeLabels[index],
                                        selected: _feeMode == mode,
                                        tone: mode == FeeMode.plus
                                            ? _BillingChoiceTone.warning
                                            : mode == FeeMode.minus
                                                ? _BillingChoiceTone.success
                                                : _BillingChoiceTone.primary,
                                        onPressed: () => _selectFeeMode(mode),
                                      );
                                    },
                                  ),
                                  AnimatedSize(
                                    duration: _reduceMotion
                                        ? Duration.zero
                                        : CommonUiMotion.layout,
                                    curve: Curves.easeOutCubic,
                                    alignment: Alignment.topCenter,
                                    child: AnimatedSwitcher(
                                      duration: _reduceMotion
                                          ? Duration.zero
                                          : CommonUiMotion.component,
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      transitionBuilder: (child, animation) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(0, .04),
                                              end: Offset.zero,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: _feeMode == FeeMode.normal
                                          ? const SizedBox.shrink(
                                              key: ValueKey<String>(
                                                'normal-mode',
                                              ),
                                            )
                                          : Padding(
                                              key: ValueKey<FeeMode>(_feeMode),
                                              padding:
                                                  const EdgeInsets.only(top: 12),
                                              child: _BillingAdjustmentCard(
                                                amountKey: _amountKey,
                                                reasonKey: _reasonKey,
                                                amountFocus: _amountFocus,
                                                reasonFocus: _reasonFocus,
                                                amountController:
                                                    _amountController,
                                                reasonController:
                                                    _reasonController,
                                                feeMode: _feeMode,
                                                onAmountTap: () =>
                                                    _ensureVisible(
                                                  _amountKey.currentContext,
                                                ),
                                                onReasonTap: () =>
                                                    _ensureVisible(
                                                  _reasonKey.currentContext,
                                                ),
                                                onAmountChanged: (value) {
                                                  setState(() {
                                                    _userAdjustment =
                                                        int.tryParse(value) ?? 0;
                                                  });
                                                },
                                                onReasonChanged: (value) {
                                                  setState(() {
                                                    _inputReason = value.trim();
                                                  });
                                                },
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _BillingReveal(
                            order: 4,
                            child: _BillingAmountSummary(
                              amount: lockedFee,
                              formatter: formatCurrency,
                              feeMode: _feeMode,
                              adjustment: _userAdjustment,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    _BillingBottomActions(
                      enabled: _isSubmitEnabled,
                      amount: lockedFee,
                      formatter: formatCurrency,
                      onSubmit: () => _submit(lockedFee),
                      onCancel: _cancel,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BillingHeader extends StatelessWidget {
  const _BillingHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: tokens.handle,
              borderRadius: BorderRadius.circular(CommonUiShapes.pill),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(CommonUiShapes.card),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: tokens.onAccentContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '정산',
                      style: textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '금액과 지불 방법을 확인한 뒤 정산을 완료합니다.',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BillingSection extends StatelessWidget {
  const _BillingSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 18,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: tokens.accent,
                borderRadius: BorderRadius.circular(CommonUiShapes.pill),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: child,
        ),
      ],
    );
  }
}

class _BillingInfoRowData {
  const _BillingInfoRowData({required this.label, required this.value});

  final String label;
  final String value;
}

class _BillingInfoCard extends StatelessWidget {
  const _BillingInfoCard({required this.rows});

  final List<_BillingInfoRowData> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      rows[index].label,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
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
              Divider(height: 1, color: tokens.borderSubtle.withOpacity(.7)),
          ],
        ],
      ),
    );
  }
}

class _BillingChoiceGrid extends StatelessWidget {
  const _BillingChoiceGrid({
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 310;
        if (!horizontal) {
          return Column(
            children: [
              for (var index = 0; index < itemCount; index++) ...[
                itemBuilder(context, index),
                if (index != itemCount - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < itemCount; index++) ...[
              Expanded(child: itemBuilder(context, index)),
              if (index != itemCount - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }
}

enum _BillingChoiceTone {
  primary,
  success,
  warning,
}

class _BillingChoiceCard extends StatefulWidget {
  const _BillingChoiceCard({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onPressed,
    this.tone = _BillingChoiceTone.primary,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onPressed;
  final _BillingChoiceTone tone;

  @override
  State<_BillingChoiceCard> createState() => _BillingChoiceCardState();
}

class _BillingChoiceCardState extends State<_BillingChoiceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = switch (widget.tone) {
      _BillingChoiceTone.primary => tokens.accent,
      _BillingChoiceTone.success => tokens.success,
      _BillingChoiceTone.warning => tokens.warning,
    };
    final accentContainer = switch (widget.tone) {
      _BillingChoiceTone.primary => tokens.accentContainer,
      _BillingChoiceTone.success => tokens.successContainer,
      _BillingChoiceTone.warning => tokens.warningContainer,
    };
    final foreground = widget.selected ? accent : tokens.textPrimary;

    return Semantics(
      button: true,
      selected: widget.selected,
      excludeSemantics: true,
      label: widget.title,
      onTap: widget.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
          scale: _pressed ? .97 : 1,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: widget.selected
                  ? accentContainer.withOpacity(.72)
                  : tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(
                color: widget.selected ? accent.withOpacity(.68) : tokens.borderSubtle,
                width: widget.selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? accent.withOpacity(.14)
                        : tokens.surfaceOverlay,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(widget.icon, size: 18, color: foreground),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                if (widget.selected) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.check_rounded, size: 16, color: accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BillingAdjustmentCard extends StatelessWidget {
  const _BillingAdjustmentCard({
    required this.amountKey,
    required this.reasonKey,
    required this.amountFocus,
    required this.reasonFocus,
    required this.amountController,
    required this.reasonController,
    required this.feeMode,
    required this.onAmountTap,
    required this.onReasonTap,
    required this.onAmountChanged,
    required this.onReasonChanged,
  });

  final GlobalKey amountKey;
  final GlobalKey reasonKey;
  final FocusNode amountFocus;
  final FocusNode reasonFocus;
  final TextEditingController amountController;
  final TextEditingController reasonController;
  final FeeMode feeMode;
  final VoidCallback onAmountTap;
  final VoidCallback onReasonTap;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onReasonChanged;

  InputDecoration _decoration(
    BuildContext context, {
    required String label,
    Widget? prefixIcon,
    String? suffixText,
  }) {
    final tokens = CommonUiTheme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.borderSubtle),
    );
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon,
      suffixText: suffixText,
      filled: true,
      fillColor: tokens.surfaceRaised,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        borderSide: BorderSide(color: tokens.focusRing, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final adjustmentLabel = feeMode == FeeMode.plus ? '할증 금액' : '할인 금액';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay.withOpacity(.6),
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        children: [
          Container(
            key: amountKey,
            child: TextField(
              focusNode: amountFocus,
              controller: amountController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _decoration(
                context,
                label: adjustmentLabel,
                prefixIcon: Icon(
                  feeMode == FeeMode.plus
                      ? Icons.add_circle_outline_rounded
                      : Icons.remove_circle_outline_rounded,
                  color: tokens.iconSecondary,
                ),
                suffixText: '₩',
              ),
              onTap: onAmountTap,
              onChanged: onAmountChanged,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            key: reasonKey,
            child: TextField(
              focusNode: reasonFocus,
              controller: reasonController,
              textInputAction: TextInputAction.done,
              decoration: _decoration(
                context,
                label: '사유',
                prefixIcon: Icon(
                  Icons.edit_note_rounded,
                  color: tokens.iconSecondary,
                ),
              ),
              onTap: onReasonTap,
              onChanged: onReasonChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingAmountSummary extends StatelessWidget {
  const _BillingAmountSummary({
    required this.amount,
    required this.formatter,
    required this.feeMode,
    required this.adjustment,
  });

  final int amount;
  final NumberFormat formatter;
  final FeeMode feeMode;
  final int adjustment;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final adjustmentText = feeMode == FeeMode.normal
        ? '기본 계산 금액'
        : feeMode == FeeMode.plus
            ? '할증 ₩${formatter.format(adjustment)} 반영'
            : '할인 ₩${formatter.format(adjustment)} 반영';

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tokens.accentContainer.withOpacity(.62),
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(color: tokens.accent.withOpacity(.42)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.accent.withOpacity(.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.price_check_rounded,
              color: tokens.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '최종 정산 금액',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  adjustmentText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: .96, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              '₩${formatter.format(amount)}',
              key: ValueKey<int>(amount),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
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

class _BillingBottomActions extends StatelessWidget {
  const _BillingBottomActions({
    required this.enabled,
    required this.amount,
    required this.formatter,
    required this.onSubmit,
    required this.onCancel,
  });

  final bool enabled;
  final int amount;
  final NumberFormat formatter;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          border: Border(top: BorderSide(color: tokens.borderSubtle)),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow.withOpacity(.55),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 320;
            final submit = FilledButton.icon(
              onPressed: enabled ? onSubmit : null,
              icon: const Icon(Icons.check_rounded),
              label: Text('₩${formatter.format(amount)} 정산 완료'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CommonUiShapes.button),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            );
            final cancel = OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CommonUiShapes.button),
                ),
                side: BorderSide(color: tokens.borderSubtle),
                foregroundColor: tokens.textPrimary,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              child: const Text('취소'),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  submit,
                  const SizedBox(height: 8),
                  cancel,
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 2, child: submit),
                const SizedBox(width: 8),
                Expanded(child: cancel),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BillingReveal extends StatelessWidget {
  const _BillingReveal({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;

    final delayMs = order.clamp(0, 8).toInt() * 24;
    const motionMs = 190;
    final totalMs = delayMs + motionMs;
    final start = delayMs / totalMs;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Curves.linear,
      child: child,
      builder: (context, value, animatedChild) {
        final normalized = value <= start
            ? 0.0
            : ((value - start) / (1 - start)).clamp(0.0, 1.0).toDouble();
        final motion = Curves.easeOutCubic.transform(normalized);
        return Opacity(
          opacity: motion,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - motion)),
            child: animatedChild,
          ),
        );
      },
    );
  }
}
