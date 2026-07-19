import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../account/applications/user_state.dart';
import '../dev/application/area_state.dart';
import '../../shared/page/application/common/type_view_mode_state.dart';
import '../../shared/page/pages/common/parking_completed_page/parking_completed_page_shell.dart';
import '../../shared/page/widget/navigation/minor_top_navigation.dart';
import '../../shared/plate/application/minor/minor_plate_state.dart';
import '../../shared/plate/domain/enums/plate_type.dart';
import '../../shared/real_time_table/view_doc_rows_firestore_sync.dart';
import 'parking_completed_package/minor_parking_completed_real_time_table.dart';
import '../../shared/plate/widgets/parking_completed_plate_search_sheet.dart';

class MinorParkingCompletedPage extends StatefulWidget {
  const MinorParkingCompletedPage({super.key});

  static void openSearchDialog(GlobalKey key, BuildContext context) {
    (key.currentState as _MinorParkingCompletedPageState?)
        ?._showSearchDialog(context);
  }

  @override
  State<MinorParkingCompletedPage> createState() =>
      _MinorParkingCompletedPageState();
}

class _MinorParkingCompletedPageState extends State<MinorParkingCompletedPage> {
  void _log(String msg) {
    if (kDebugMode) {
      debugPrint('[ParkingCompleted] $msg');
    }
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;
    _log('open search dialog');

    showPromptOverlayBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      transparentBackground: true,
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height,
          child: ParkingCompletedPlateSearchSheet(
            area: currentArea,
            variant: ParkingCompletedSearchVariant.minor,
            onSearch: (_) {},
          ),
        );
      },
    );
  }

  Future<bool> _handleWillPop() async {
    final plateState = context.read<MinorPlateState>();
    final userName = context.read<UserState>().name;

    final selectedPlate = plateState.minorGetSelectedPlate(
      PlateType.parkingCompleted,
      userName,
    );

    if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
      await plateState.minorTogglePlateIsSelected(
        collection: PlateType.parkingCompleted,
        plateNumber: selectedPlate.plateNumber,
        userName: userName,
        onError: (msg) => debugPrint(msg),
      );
      _log('clear selection');
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<TypeViewModeState>().mode;
    final area = resolveParkingCompletedArea(context);

    return ParkingCompletedPageShell(
      topNavigation: const MinorTopNavigation(),
      semanticsLabel: 'screen_tag: MinorParkingCompletedPage',
      syncSourceTag: 'MinorParkingCompletedPage(sync)',
      syncSpecs: const [
        ViewDocSyncSpec(
          collection: 'parking_requests_view',
          primaryAtField: 'parkingRequestedAt',
        ),
        ViewDocSyncSpec(
          collection: 'parking_completed_view',
          primaryAtField: 'parkingCompletedAt',
        ),
        ViewDocSyncSpec(
          collection: 'departure_requests_view',
          primaryAtField: 'departureRequestedAt',
        ),
      ],
      onWillPop: _handleWillPop,
      content: MinorParkingCompletedRealTimeTable(
        statusPreview: mode == TypeViewMode.status,
        area: area,
      ),
    );
  }
}
