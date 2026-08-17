import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'real_time_sort_state.dart';

Future<void> showRealTimeSortPanel(BuildContext context) async {
  final state = context.read<RealTimeSortState>();
  state.togglePriority(reason: 'legacy_direct_toggle');
  debugPrint(
    '[RealTimePriority] legacy_direct_toggle priority=${state.priorityMode.name} label=${state.priorityLabel} order=${state.timeOrderLabel} selectedLocation=${state.selectedLocation}',
  );
}
