class MonthlyPaymentSettingsDraft {
  const MonthlyPaymentSettingsDraft({
    required this.paymentAmount,
    required this.extended,
    required this.note,
  });

  final int? paymentAmount;
  final bool extended;
  final String note;

  MonthlyPaymentSettingsDraft copyWith({
    int? paymentAmount,
    bool clearPaymentAmount = false,
    bool? extended,
    String? note,
  }) {
    return MonthlyPaymentSettingsDraft(
      paymentAmount:
          clearPaymentAmount ? null : paymentAmount ?? this.paymentAmount,
      extended: extended ?? this.extended,
      note: note ?? this.note,
    );
  }

  MonthlyPaymentSettingsDraft detached() {
    return MonthlyPaymentSettingsDraft(
      paymentAmount: paymentAmount,
      extended: extended,
      note: note,
    );
  }
}
