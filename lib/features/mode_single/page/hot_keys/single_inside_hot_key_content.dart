import 'package:flutter/material.dart';

import '../side_docks/single_inside_side_dock.dart';

enum SingleInsideHotKeyContent {
  parkingArea,
  workSchedule,
  workRules,
  workManual,
  workStartReport,
  workEndReport,
  commuteSubmit,
  restTimeSubmit,
}

extension SingleInsideHotKeyContentUi on SingleInsideHotKeyContent {
  String get title {
    switch (this) {
      case SingleInsideHotKeyContent.parkingArea:
        return '주차 구역';
      case SingleInsideHotKeyContent.workSchedule:
        return '일정 수정';
      case SingleInsideHotKeyContent.workRules:
        return '업무 규칙';
      case SingleInsideHotKeyContent.workManual:
        return '업무 메뉴얼';
      case SingleInsideHotKeyContent.workStartReport:
        return '업무 시작 보고';
      case SingleInsideHotKeyContent.workEndReport:
        return '업무 종료 보고';
      case SingleInsideHotKeyContent.commuteSubmit:
        return '출퇴근 제출';
      case SingleInsideHotKeyContent.restTimeSubmit:
        return '휴게 제출';
    }
  }

  IconData get icon {
    switch (this) {
      case SingleInsideHotKeyContent.parkingArea:
        return Icons.local_parking_rounded;
      case SingleInsideHotKeyContent.workSchedule:
        return Icons.calendar_month_rounded;
      case SingleInsideHotKeyContent.workRules:
        return Icons.rule_rounded;
      case SingleInsideHotKeyContent.workManual:
        return Icons.menu_book_rounded;
      case SingleInsideHotKeyContent.workStartReport:
        return Icons.play_circle_outline_rounded;
      case SingleInsideHotKeyContent.workEndReport:
        return Icons.stop_circle_outlined;
      case SingleInsideHotKeyContent.commuteSubmit:
        return Icons.cloud_upload_outlined;
      case SingleInsideHotKeyContent.restTimeSubmit:
        return Icons.coffee_rounded;
    }
  }

  SingleInsideDockRequest get request {
    switch (this) {
      case SingleInsideHotKeyContent.parkingArea:
        return SingleInsideDockRequest.parkingArea;
      case SingleInsideHotKeyContent.workSchedule:
        return SingleInsideDockRequest.workSchedule;
      case SingleInsideHotKeyContent.workRules:
        return SingleInsideDockRequest.workRules;
      case SingleInsideHotKeyContent.workManual:
        return SingleInsideDockRequest.workManual;
      case SingleInsideHotKeyContent.workStartReport:
        return SingleInsideDockRequest.workStartReport;
      case SingleInsideHotKeyContent.workEndReport:
        return SingleInsideDockRequest.workEndReport;
      case SingleInsideHotKeyContent.commuteSubmit:
        return SingleInsideDockRequest.commuteSubmit;
      case SingleInsideHotKeyContent.restTimeSubmit:
        return SingleInsideDockRequest.restTimeSubmit;
    }
  }
}

class SingleInsideHotKeyConfig {
  const SingleInsideHotKeyConfig({
    required this.slot1,
    required this.slot2,
    required this.slot3,
    required this.slot4,
  });

  final SingleInsideHotKeyContent? slot1;
  final SingleInsideHotKeyContent? slot2;
  final SingleInsideHotKeyContent? slot3;
  final SingleInsideHotKeyContent? slot4;

  List<SingleInsideHotKeyContent?> get slots => <SingleInsideHotKeyContent?>[
        slot1,
        slot2,
        slot3,
        slot4,
      ];

  SingleInsideHotKeyContent? contentAt(int slot) {
    switch (slot) {
      case 1:
        return slot1;
      case 2:
        return slot2;
      case 3:
        return slot3;
      case 4:
        return slot4;
      default:
        throw RangeError.range(slot, 1, 4, 'slot');
    }
  }

  SingleInsideHotKeyConfig replaceSlot(
    int slot,
    SingleInsideHotKeyContent? value,
  ) {
    switch (slot) {
      case 1:
        return SingleInsideHotKeyConfig(
          slot1: value,
          slot2: slot2,
          slot3: slot3,
          slot4: slot4,
        );
      case 2:
        return SingleInsideHotKeyConfig(
          slot1: slot1,
          slot2: value,
          slot3: slot3,
          slot4: slot4,
        );
      case 3:
        return SingleInsideHotKeyConfig(
          slot1: slot1,
          slot2: slot2,
          slot3: value,
          slot4: slot4,
        );
      case 4:
        return SingleInsideHotKeyConfig(
          slot1: slot1,
          slot2: slot2,
          slot3: slot3,
          slot4: value,
        );
      default:
        throw RangeError.range(slot, 1, 4, 'slot');
    }
  }

  bool get hasDuplicate {
    final selected = slots.whereType<SingleInsideHotKeyContent>().toList();
    return selected.toSet().length != selected.length;
  }
}
