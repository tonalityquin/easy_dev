import 'package:flutter/material.dart';

/// 요금 계산 방식 열거형
enum FeeMode { normal, plus, minus }

/// 정산 유형 열거형 (한글 대신 영문으로 작성)
enum BillType { general, fixed }

/// 문자열 → Enum 변환 함수
BillType billTypeFromString(String? value) {
  if (value == null) return BillType.general;

  final normalized = value.toLowerCase(); // 소문자 처리

  if (normalized.contains('고정') ||
      normalized.contains('fixed') ||
      normalized.contains('daily') ||
      normalized.contains('일일') ||
      normalized.contains('정기')) {
    return BillType.fixed;
  }

  return BillType.general;
}

/// Enum → 문자열 변환 함수 (필요 시 UI용)
String billTypeToString(BillType type) {
  return type == BillType.fixed ? '고정' : '변동';
}

/// 통합된 요금 계산 함수 (고정/변동 주차 포함)
int calculateFee({
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard, // 분 단위
  required int basicAmount,
  required int addStandard, // 분 단위
  required int addAmount,
  int userAdjustment = 0,
  FeeMode mode = FeeMode.normal,

  // 고정 정산용 필드
  String? billingType, // e.g., '고정' 또는 '변동'
  int? regularAmount,
}) {
  final billType = billTypeFromString(billingType);
  final isRegular = billType == BillType.fixed;

  // 1. 고정 정산
  if (isRegular) {
    final base = regularAmount ?? 0;

    switch (mode) {
      case FeeMode.normal:
        return base;
      case FeeMode.plus:
        return base + userAdjustment;
      case FeeMode.minus:
        final adjusted = base - userAdjustment;
        return adjusted < 0 ? 0 : adjusted;
    }
  }

  // 2. 변동 정산
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

  // 3. 조정 적용
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
