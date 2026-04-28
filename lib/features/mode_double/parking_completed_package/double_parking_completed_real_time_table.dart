import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/preview_package/parking_grid_3d_preview.dart';
import '../../../../shared/preview_package/parking_status_preview_card_area.dart';
import '../../../../shared/real_time_table/real_time_status_preview_body.dart';
import '../../../../shared/real_time_table/real_time_table.dart';
import 'widgets/double_parking_completed_status_bottom_sheet.dart';

class ParkingCompletedRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'parking_completed_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async => true;

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, true);
  }
}

class DoubleParkingCompletedRealTimeTable extends StatelessWidget {
  final VoidCallback? onClose;
  final bool statusPreview;
  final String area;

  const DoubleParkingCompletedRealTimeTable({
    super.key,
    this.onClose,
    this.statusPreview = false,
    this.area = '',
  });

  @override
  Widget build(BuildContext context) {
    final tabs = <RealTimeTabSpec>[
      RealTimeTabSpec(
        id: 'parking_completed',
        label: '입차 완료',
        collection: 'parking_completed_view',
        zoneSupported: true,
        syncLocationCounts: false,
        showUnknownInZoneSummary: false,
        labelUsesAccent: true,
        defaultSortOldFirst: true,
        isEnabled: ParkingCompletedRealtimeTabGate.isEnabled,
        accent: (cs) => cs.primary,
        tableNoStrategy: LinearNoStrategy(),
        dialogNoStrategy: LinearNoStrategy(),
        openBottomSheet: (ctx, plate) =>
            showDoubleParkingCompletedStatusBottomSheetFromDialog(
          context: ctx,
          plate: plate,
          popParentOnDelete: false,
        ),
      ),
    ];

    final style = RealTimeTabBarStyle(
      containerColor: (cs) => cs.surface,
      pillColor: (cs) => cs.primary.withOpacity(.04),
      borderColor: (cs) => cs.outlineVariant.withOpacity(.7),
    );

    return RealTimeTabbedTable(
      tabs: tabs,
      tabBarStyle: style,
      initialIndex: 0,
      screen: 'double_parking_completed_view_embedded',
      description: '자동 갱신됩니다.',
      viewModeAuto: const RealTimeViewModeAutoSpec(),
      bodyBuilder: statusPreview
          ? (ctx, spec, ctrl) => RealTimeStatusPreviewBody(
                controller: ctrl,
                area: area,
                overlay: const <ParkingStatusOverlaySpec>[
                  ParkingStatusOverlaySpec(
                    collection: 'parking_completed_view',
                    status: ParkingSlotStatus.parked,
                  ),
                ],
              )
          : null,
    );
  }
}
