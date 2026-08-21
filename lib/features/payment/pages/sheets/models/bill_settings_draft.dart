class BillSettingsDraft {
  const BillSettingsDraft({
    required this.countType,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
  });

  final String countType;
  final int? basicStandard;
  final int? basicAmount;
  final int? addStandard;
  final int? addAmount;

  BillSettingsDraft copyWith({
    String? countType,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
  }) {
    return BillSettingsDraft(
      countType: countType ?? this.countType,
      basicStandard: basicStandard ?? this.basicStandard,
      basicAmount: basicAmount ?? this.basicAmount,
      addStandard: addStandard ?? this.addStandard,
      addAmount: addAmount ?? this.addAmount,
    );
  }

  BillSettingsDraft detached() {
    return BillSettingsDraft(
      countType: countType,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
    );
  }
}
