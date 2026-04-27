import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common_package/real_time_table/real_time_table.dart';
import '../../../common_package/real_time_table/real_time_status_preview_body.dart';
import '../../../common_package/preview_package/parking_grid_3d_preview.dart';
import '../../../common_package/preview_package/parking_status_preview_card_area.dart';

import 'widgets/triple_parking_completed_status_bottom_sheet.dart';

class DepartureRequestsRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'departure_requests_realtime_tab_enabled_v1';

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

class TripleParkingCompletedRealTimeTable extends StatelessWidget {
  final VoidCallback? onClose;
  final bool statusPreview;
  final String area;

  const TripleParkingCompletedRealTimeTable({
    super.key,
    this.onClose,
    this.statusPreview = false,
    this.area = '',
  });

  @override
  Widget build(BuildContext context) {
    final no = DayNewestRankNoStrategy();

    final tabs = <RealTimeTabSpec>[
      RealTimeTabSpec(
        id: 'parking_completed',
        label: '입차 완료',
        collection: 'parking_completed_view',
        zoneSupported: true,
        syncLocationCounts: true,
        showUnknownInZoneSummary: true,
        labelUsesAccent: false,
        defaultSortOldFirst: true,
        detailConfirmMessage: '원본 데이터를 불러옵니다.\n(취소하면 조회 비용이 발생하지 않습니다)',
        isEnabled: ParkingCompletedRealtimeTabGate.isEnabled,
        accent: (cs) => cs.primary,
        tableNoStrategy: no,
        dialogNoStrategy: no,
        openBottomSheet: (ctx, plate) =>
            showTripleParkingCompletedStatusBottomSheetFromDialog(
          context: ctx,
          plate: plate,
          popParentOnDelete: false,
        ),
      ),
      RealTimeTabSpec(
        id: 'departure_requests',
        label: '출차 요청',
        collection: 'departure_requests_view',
        zoneSupported: true,
        syncLocationCounts: true,
        showUnknownInZoneSummary: true,
        labelUsesAccent: false,
        defaultSortOldFirst: true,
        detailConfirmMessage: '원본 데이터를 불러옵니다.\n(취소하면 조회 비용이 발생하지 않습니다)',
        isEnabled: DepartureRequestsRealtimeTabGate.isEnabled,
        accent: (cs) => cs.secondary,
        tableNoStrategy: no,
        dialogNoStrategy: no,
        openBottomSheet: (ctx, plate) =>
            showTripleParkingCompletedStatusBottomSheetFromDialog(
          context: ctx,
          plate: plate,
          popParentOnDelete: false,
        ),
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
      initialIndex: 0,
      screen: 'triple_reverse_table_embedded',
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
