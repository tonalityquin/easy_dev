import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../features/account/applications/user_state.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../shared/page/application/common/type_view_mode_state.dart';
import '../../../shared/page/pages/common/parking_completed_page/parking_completed_page_shell.dart';
import '../../../shared/page/widget/navigation/triple_top_navigation.dart';
import '../../../shared/plate/application/triple/triple_plate_state.dart';
import '../../../shared/plate/domain/enums/plate_type.dart';
import '../../../shared/real_time_table/view_doc_rows_firestore_sync.dart';
import 'parking_completed_package/triple_parking_completed_real_time_table.dart';
import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/triple_parking_completed_search_bottom_sheet.dart';

class TripleParkingCompletedPage extends StatefulWidget {
  const TripleParkingCompletedPage({super.key});

  static void openSearchDialog(GlobalKey key, BuildContext context) {
    (key.currentState as _TripleParkingCompletedPageState?)
        ?._showSearchDialog(context);
  }

  @override
  State<TripleParkingCompletedPage> createState() =>
      _TripleParkingCompletedPageState();
}

class _TripleParkingCompletedPageState
    extends State<TripleParkingCompletedPage> {
  void _log(String msg) {
    if (kDebugMode) {
      debugPrint('[ParkingCompleted] $msg');
    }
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;
    _log('open search dialog');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height,
          child: TripleParkingCompletedSearchBottomSheet(
            onSearch: (_) {},
            area: currentArea,
          ),
        );
      },
    );
  }

  Future<bool> _handleWillPop() async {
    final plateState = context.read<TriplePlateState>();
    final userName = context.read<UserState>().name;

    final selectedPlate = plateState.tripleGetSelectedPlate(
      PlateType.parkingCompleted,
      userName,
    );

    if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
      await plateState.tripleTogglePlateIsSelected(
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
    final cs = Theme.of(context).colorScheme;
    final mode = context.watch<TypeViewModeState>().mode;
    final area = resolveParkingCompletedArea(context);

    return ParkingCompletedPageShell(
      topNavigation: const TripleTopNavigation(),
      semanticsLabel: 'screen_tag: TripleParkingCompletedPage',
      syncSourceTag: 'TripleParkingCompletedPage(sync)',
      syncSpecs: const [
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
      scaffoldBackgroundColor: cs.surface,
      content: TripleParkingCompletedRealTimeTable(
        statusPreview: mode == TypeViewMode.status,
        area: area,
      ),
    );
  }
}
