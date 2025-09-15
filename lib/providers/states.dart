import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../repositories/bill_repo_services/bill_repository.dart';
import '../repositories/location_repo_services/firestore_location_repository.dart';
import '../repositories/plate_repo_services/plate_repository.dart';
import '../repositories/user_repo_services/user_repository.dart';

import '../screens/head_package/calendar_package/calendar_model.dart';
import '../screens/head_package/calendar_package/google_calendar_service.dart';

// ▼ Dev 캘린더 전역 주입을 위한 추가 import
import '../screens/dev_package/dev_calendar_package/dev_calendar_model.dart';
import '../screens/dev_package/dev_calendar_package/dev_google_calendar_service.dart';

import '../screens/tablet_package/states/tablet_pad_mode_state.dart';
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
import '../states/user/user_state.dart';

final List<SingleChildWidget> stateProviders = [
  ChangeNotifierProvider(
    create: (context) => PageState(pages: defaultPages),
  ),
  ChangeNotifierProvider(
    create: (_) => AreaState(),
  ),
  ChangeNotifierProvider(
    create: (_) => TabletPadModeState(),
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
  // 본사(운영) 캘린더 모델
  ChangeNotifierProvider(
    create: (_) => CalendarModel(GoogleCalendarService()),
  ),
  // ▼ 개발용 Dev 캘린더 모델(CompanyCalendarPage와 동일 패턴의 전역 주입)
  ChangeNotifierProvider(
    create: (_) => DevCalendarModel(DevGoogleCalendarService()),
  ),
];
