import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../repositories/bill_repo/bill_repository.dart';
import '../repositories/location/firestore_location_repository.dart';
import '../repositories/plate/plate_repository.dart';
import '../repositories/user/user_repository.dart';

import '../states/area/area_state.dart';
import '../states/bill/bill_state.dart';
import '../states/calendar/field_calendar_state.dart';
import '../states/head_quarter/calendar_selection_state.dart';
import '../states/location/location_state.dart';
import '../states/page/page_info.dart';
import '../states/page/page_state.dart';
import '../states/plate/input_log_plate.dart';
import '../states/plate/modify_plate.dart';
import '../states/plate/input_plate.dart';
import '../states/plate/plate_state.dart';
import '../states/plate/filter_plate.dart';
import '../states/plate/delete_plate.dart';
import '../states/plate/movement_plate.dart';
import '../states/secondary/secondary_mode.dart';
import '../states/user/user_state.dart';

final List<SingleChildWidget> stateProviders = [
  ChangeNotifierProvider(
    create: (context) => PageState(pages: defaultPages),
  ),
  ChangeNotifierProvider(
    create: (_) => AreaState(),
  ),
  ChangeNotifierProvider(
    create: (_) => SecondaryMode(),
  ),
  ChangeNotifierProvider(
    create: (_) => InputLogPlate(),
  ),
  ChangeNotifierProvider(
    create: (context) => ModifyPlate(
      context.read<PlateRepository>(),
    ),
  ),
  ChangeNotifierProvider(
    create: (context) => InputPlate(
      context.read<PlateRepository>(),
      context.read<InputLogPlate>(),
    ),
  ),
  ChangeNotifierProvider(
    create: (context) {
      final repo = context.read<PlateRepository>();
      final area = context.read<AreaState>();
      return PlateState(repo, area);
    },
  ),
  ChangeNotifierProvider(
    create: (context) => FilterPlate(
      context.read<PlateState>(),
    ),
  ),
  Provider(
    create: (context) => DeletePlate(
      context.read<PlateRepository>(),
      {},
    ),
  ),
  Provider(
    create: (context) => MovementPlate(
      context.read<PlateRepository>(),
    ),
  ),
  ChangeNotifierProvider(
    create: (context) => UserState(
      context.read<UserRepository>(),
      context.read<AreaState>(),
    ),
  ),
  ChangeNotifierProvider(
    create: (context) => LocationState(
      FirestoreLocationRepository(),
      context.read<AreaState>(),
    ),
  ),
  ChangeNotifierProvider(
    create: (context) {
      final repo = context.read<BillRepository>();
      final area = context.read<AreaState>();
      return BillState(repo, area);
    },
  ),
  ChangeNotifierProvider(
    create: (_) => FieldSelectedDateState(),
  ),
  ChangeNotifierProvider(
    create: (_) => CalendarSelectionState(),
  ),
];
