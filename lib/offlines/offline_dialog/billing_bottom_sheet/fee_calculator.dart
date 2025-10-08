import 'package:flutter/material.dart';

/// 요금 계산 방식 열거형
enum FeeMode { normal, plus, minus }

/// 정산 유형 열거형 (호환성 유지용)
/// - 'fixed' 값은 과거 참조를 깨지 않기 위해 남겨두지만, 로직에서는 더 이상 사용하지 않습니다.
enum BillType { general, fixed }

/// 문자열 → Enum 변환 함수
/// - '고정' / '정기' 등은 더 이상 인식하지 않고 항상 변동으로 처리합니다.
BillType billTypeFromString(String? value) {
  // '고정' 및 '정기' 인식 제거 → 항상 변동으로 간주
  return BillType.general;
}

/// Enum → 문자열 변환 함수 (UI 표시용)
/// - 항상 '변동'으로 반환하여 '고정' 레이블을 노출하지 않음
String billTypeToString(BillType type) {
  return '변동';
}

/// 통합 요금 계산 (변동만 처리)
/// - 기존 '고정' 분기(regularAmount 사용)는 완전히 제거
/// - billingType/regularAmount 파라미터는 호환성 위해 남겨두되 미사용
int calculateFee({
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard, // 분 단위
  required int basicAmount,
  required int addStandard,   // 분 단위
  required int addAmount,
  int userAdjustment = 0,
  FeeMode mode = FeeMode.normal,

  // (구) 고정 정산 관련 파라미터 — 더 이상 사용하지 않음(호환성 목적)
  String? billingType, // e.g., '고정' 또는 '변동' (무시됨)
  int? regularAmount,  // 무시됨
}) {
  // 모든 경우를 변동(시간제) 정산으로 처리합니다.

  // 1) 경과 시간 계산
  final parkedSeconds = currentTimeInSeconds - entryTimeInSeconds;
  final basicSec = basicStandard * 60;
  final addSec = addStandard * 60;

  // 2) 기본/추가 요금 계산
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

  // 3) 조정 적용
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
