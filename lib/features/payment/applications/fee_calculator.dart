import 'package:flutter/material.dart';

enum FeeMode { normal, plus, minus }

enum BillType { general, fixed }

BillType billTypeFromString(String? value) {
  return BillType.general;
}

String billTypeToString(BillType type) {
  return '변동';
}

int calculateFee({
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard,
  required int basicAmount,
  required int addStandard,
  required int addAmount,
  int userAdjustment = 0,
  FeeMode mode = FeeMode.normal,
  String? billingType,
  int? regularAmount,
}) {
  final parkedSeconds = currentTimeInSeconds - entryTimeInSeconds;
  final basicSec = basicStandard * 60;
  final addSec = addStandard * 60;

  int baseFee;
  if (parkedSeconds <= basicSec) {
    baseFee = basicAmount;
  } else {
    final extraTime = parkedSeconds - basicSec;
    int extraUnits = 0;
    if (addSec > 0) {
      extraUnits = (extraTime / addSec).ceil();
    } else {
      debugPrint("⚠️ addStandard가 0이므로 추가 요금 계산 생략");
    }
    baseFee = basicAmount + (extraUnits * addAmount);
  }

  switch (mode) {
    case FeeMode.normal:
      return baseFee;
    case FeeMode.plus:
      return baseFee + userAdjustment;
    case FeeMode.minus:
      final discounted = baseFee - userAdjustment;
      return discounted < 0 ? 0 : discounted;
  }
}
