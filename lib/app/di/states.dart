import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../features/account/applications/user_state.dart';
import '../../features/account/domain/repositories/user_repository.dart';
import '../../features/dashboard/applications/common/calendar_selection_state.dart';
import '../../features/dev/application/area_state.dart';
import '../../features/dev/application/field_calendar_state.dart';
import '../../features/dev/domain/repositories/area_repo_package/area_repository.dart';
import '../../features/headquarter/widgets/calendar/calendar_model.dart';
import '../../features/headquarter/widgets/calendar/google_calendar_service.dart';
import '../../features/location/applications/location_state.dart';
import '../../features/location/data/repositories/firestore_location_repository.dart';
import '../../features/payment/applications/bill_state.dart';
import '../../features/payment/domain/repositories/bill_repository.dart';
import '../../features/tablet/applications/tablet_pad_mode_state.dart';
import '../../features/tablet/applications/tablet_parking_completed_view_toggle_state.dart';
import '../../features/tablet/applications/tablet_work_session_state.dart';
import '../../shared/plate/application/common/delete_plate.dart';
import '../../shared/plate/application/common/input_plate.dart';
import '../../shared/plate/application/common/movement_plate.dart';
import '../../shared/plate/application/common/view_doc_rows_store.dart';
import '../../shared/plate/application/double/double_filter_plate.dart';
import '../../shared/plate/application/double/double_plate_state.dart';
import '../../shared/plate/application/minor/minor_filter_plate.dart';
import '../../shared/plate/application/minor/minor_plate_state.dart';
import '../../shared/plate/application/triple/triple_filter_plate.dart';
import '../../shared/plate/application/triple/triple_plate_state.dart';
import '../../shared/plate/domain/repositories/plate_repository.dart';
import '../../shared/plate/domain/services/plate_write_service.dart';
import '../../shared/secondary/application/secondary_info.dart';
import '../../shared/secondary/application/secondary_state.dart';

final List<SingleChildWidget> stateProviders = [
  ChangeNotifierProvider(
    create: (context) => AreaState(context.read<AreaRepository>()),
  ),
  ChangeNotifierProvider(create: (_) => ViewDocRowsStore()),
  ChangeNotifierProvider(create: (_) => TabletPadModeState()),
  ChangeNotifierProvider(create: (_) => TabletWorkSessionState()),
  ChangeNotifierProvider(
    create: (_) => TabletParkingCompletedViewToggleState(),
  ),
  ChangeNotifierProvider(
    create: (context) => InputPlate(context.read<PlateRepository>()),
  ),
  ChangeNotifierProvider(
    create: (context) {
      final repo = context.read<PlateRepository>();
      final area = context.read<AreaState>();
      return DoublePlateState(repo, area);
    },
  ),
  ChangeNotifierProvider(
    create: (context) => DoubleFilterPlate(context.read<DoublePlateState>()),
  ),
  ChangeNotifierProvider(
    create: (context) {
      final repo = context.read<PlateRepository>();
      final area = context.read<AreaState>();
      return TriplePlateState(repo, area);
    },
  ),
  ChangeNotifierProvider(
    create: (context) => TripleFilterPlate(context.read<TriplePlateState>()),
  ),
  ChangeNotifierProvider(
    create: (context) {
      final repo = context.read<PlateRepository>();
      final area = context.read<AreaState>();
      return MinorPlateState(repo, area);
    },
  ),
  ChangeNotifierProvider(
    create: (context) => MinorFilterPlate(context.read<TriplePlateState>()),
  ),
  Provider(
    create: (context) => DeletePlate(context.read<PlateRepository>(), {}),
  ),
  ChangeNotifierProvider(
    create: (context) => UserState(
      context.read<UserRepository>(),
      context.read<AreaState>(),
    ),
  ),
  Provider(create: (_) => PlateWriteService()),
  ChangeNotifierProvider(
    create: (context) => MovementPlate(
      context.read<PlateRepository>(),
      context.read<UserState>(),
    ),
  ),
  ChangeNotifierProvider(
    create: (context) => LocationState(
      FirestoreLocationRepository(),
      context.read<AreaState>(),
    ),
  ),
  ChangeNotifierProvider(
    create: (context) => BillState(
      context.read<BillRepository>(),
      context.read<AreaState>(),
    ),
  ),
  ChangeNotifierProvider(create: (_) => FieldSelectedDateState()),
  ChangeNotifierProvider(create: (_) => CalendarSelectionState()),
  ChangeNotifierProvider(create: (_) => CalendarModel(GoogleCalendarService())),
  ChangeNotifierProxyProvider2<UserState, AreaState, SecondaryState>(
    create: (_) => SecondaryState(),
    update: (ctx, userState, areaState, secondaryState) {
      final state = secondaryState ?? SecondaryState();
      final role = RoleType.fromName(userState.role);
      final caps = areaState.capabilitiesOfCurrentArea;

      state.updateAccess(role: role, areaCaps: caps);
      return state;
    },
  ),
];
