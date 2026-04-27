import 'package:flutter/material.dart';

import '../../../features/plate/domain/models/plate_model.dart';
import 'real_time_table_no_strategy.dart';

class RealTimeTabSpec {
  final String id;
  final String label;
  final String collection;
  final bool zoneSupported;
  final bool syncLocationCounts;
  final bool showUnknownInZoneSummary;
  final bool labelUsesAccent;
  final bool defaultSortOldFirst;
  final String detailConfirmMessage;

  final Future<bool> Function() isEnabled;
  final Color Function(ColorScheme cs) accent;

  final NoStrategy tableNoStrategy;
  final NoStrategy dialogNoStrategy;

  final Future<void> Function(BuildContext ctx, PlateModel plate)
      openBottomSheet;

  const RealTimeTabSpec({
    required this.id,
    required this.label,
    required this.collection,
    required this.zoneSupported,
    required this.syncLocationCounts,
    required this.showUnknownInZoneSummary,
    required this.labelUsesAccent,
    required this.defaultSortOldFirst,
    this.detailConfirmMessage = '',
    required this.isEnabled,
    required this.accent,
    required this.tableNoStrategy,
    required this.dialogNoStrategy,
    required this.openBottomSheet,
  });
}

class RealTimeTabBarStyle {
  final Color Function(ColorScheme cs) containerColor;
  final Color Function(ColorScheme cs) pillColor;
  final Color Function(ColorScheme cs) borderColor;

  const RealTimeTabBarStyle({
    required this.containerColor,
    required this.pillColor,
    required this.borderColor,
  });
}
