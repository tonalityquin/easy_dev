import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../shared/preview_package/parking_grid_3d_preview.dart';
import '../../../../shared/preview_package/parking_status_preview_card_area.dart';
import '../../../../shared/real_time_table/real_time_status_preview_body.dart';
import '../../../../shared/real_time_table/real_time_table.dart';
import 'widgets/minor_parking_completed_status_bottom_sheet.dart';

class DepartureRequestsRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'departure_requests_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async => true;

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, true);
  }
}

class ParkingRequestsRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'parking_requests_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async => true;

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, true);
  }
}

class ParkingCompletedRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'parking_completed_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async => true;

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, true);
  }
}

class MinorParkingCompletedRealTimeTable extends StatelessWidget {
  final VoidCallback? onClose;
  final bool statusPreview;
  final String area;

  const MinorParkingCompletedRealTimeTable({
    super.key,
    this.onClose,
    this.statusPreview = false,
    this.area = '',
  });

  @override
  Widget build(BuildContext context) {
    final tableNo = DayGroupNoStrategy();
    final dialogNo = LinearNoStrategy();

    Future<void> openSheet(BuildContext ctx, plate) {
      return showMinorParkingCompletedStatusBottomSheetFromDialog(
        context: ctx,
        plate: plate,
        popParentOnDelete: false,
      );
    }

    final tabs = <RealTimeTabSpec>[
      RealTimeTabSpec(
        id: 'parking_requests',
        label: '입차 요청',
        collection: 'parking_requests_view',
        zoneSupported: false,
        syncLocationCounts: true,
        showUnknownInZoneSummary: false,
        labelUsesAccent: true,
        defaultSortOldFirst: false,
        isEnabled: ParkingRequestsRealtimeTabGate.isEnabled,
        accent: (cs) => cs.secondary,
        tableNoStrategy: tableNo,
        dialogNoStrategy: dialogNo,
        openBottomSheet: (ctx, plate) => openSheet(ctx, plate),
      ),
      RealTimeTabSpec(
        id: 'parking_completed',
        label: '입차 완료',
        collection: 'parking_completed_view',
        zoneSupported: true,
        syncLocationCounts: true,
        showUnknownInZoneSummary: false,
        labelUsesAccent: true,
        defaultSortOldFirst: false,
        isEnabled: ParkingCompletedRealtimeTabGate.isEnabled,
        accent: (cs) => cs.primary,
        tableNoStrategy: tableNo,
        dialogNoStrategy: dialogNo,
        openBottomSheet: (ctx, plate) => openSheet(ctx, plate),
      ),
      RealTimeTabSpec(
        id: 'departure_requests',
        label: '출차 요청',
        collection: 'departure_requests_view',
        zoneSupported: true,
        syncLocationCounts: true,
        showUnknownInZoneSummary: false,
        labelUsesAccent: true,
        defaultSortOldFirst: false,
        isEnabled: DepartureRequestsRealtimeTabGate.isEnabled,
        accent: (cs) => cs.tertiary,
        tableNoStrategy: tableNo,
        dialogNoStrategy: dialogNo,
        openBottomSheet: (ctx, plate) => openSheet(ctx, plate),
      ),
    ];

    final style = RealTimeTabBarStyle(
      containerColor: (cs) => cs.surface,
      pillColor: (cs) => cs.surfaceContainerLow,
      borderColor: (cs) => cs.outlineVariant.withOpacity(0.85),
    );

    return RealTimeTabbedTable(
      tabs: tabs,
      tabBarStyle: style,
      initialIndex: 1,
      screen: 'minor_reverse_table_embedded',
      description: '자동 갱신됩니다.',
      viewModeAuto: const RealTimeViewModeAutoSpec(),
      bodyBuilder: statusPreview
          ? (ctx, spec, ctrl) => RealTimeStatusPreviewBody(
                controller: ctrl,
                area: area,
                overlay: const <ParkingStatusOverlaySpec>[
                  ParkingStatusOverlaySpec(
                    collection: 'parking_requests_view',
                    status: ParkingSlotStatus.parkingRequest,
                  ),
                  ParkingStatusOverlaySpec(
                    collection: 'parking_completed_view',
                    status: ParkingSlotStatus.parked,
                  ),
                  ParkingStatusOverlaySpec(
                    collection: 'departure_requests_view',
                    status: ParkingSlotStatus.departureRequest,
                  ),
                ],
              )
          : null,
    );
  }
}
