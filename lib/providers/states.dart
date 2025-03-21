import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../repositories/location/firestore_location_repository.dart';
import '../repositories/status/firestore_status_repository.dart';
import '../states/secondary/secondary_access_state.dart';
import '../states/page/page_state.dart';
import '../states/plate/filter_plate.dart';
import '../states/plate/input_plate.dart';
import '../states/plate/plate_state.dart';
import '../states/plate/delete_plate.dart';
import '../states/plate/movement_plate.dart'; // ✅ MovementPlate 추가
import '../states/page/page_info.dart';
import '../states/area/area_state.dart';
import '../states/user/user_state.dart';
import '../states/location/location_state.dart';
import '../states/adjustment/adjustment_state.dart';
import '../states/status/status_state.dart';
import '../repositories/adjustment/adjustment_repository.dart';
import '../repositories/status/status_repository.dart';
import '../repositories/plate/plate_repository.dart';
import '../repositories/user/user_repository.dart';

final List<SingleChildWidget> stateProviders = [
  ChangeNotifierProvider(create: (context) => PageState(pages: defaultPages)),
  ChangeNotifierProvider(create: (_) => AreaState()),
  ChangeNotifierProvider(create: (context) => SecondaryAccessState()),
  ChangeNotifierProvider(
    create: (context) => InputPlate(context.read<PlateRepository>()),
  ),
  ChangeNotifierProvider(
    create: (context) {
      final repo = context.read<PlateRepository>();
      final areaState = context.read<AreaState>();
      return PlateState(repo, areaState);
    },
  ),
  ChangeNotifierProvider(
    create: (context) => UserState(context.read<UserRepository>()),
  ),
  ChangeNotifierProvider(
    create: (context) => LocationState(FirestoreLocationRepository()),
  ),
  ChangeNotifierProvider(
    create: (context) {
      final areaState = context.read<AreaState>();
      return AdjustmentState(
        context.read<AdjustmentRepository>(),
        areaState,
      );
    },
  ),
  ChangeNotifierProvider(
    create: (context) {
      final statusRepo = context.read<StatusRepository?>();
      final areaState = context.read<AreaState>();
      if (statusRepo == null) {
        return StatusState(FirestoreStatusRepository(), areaState);
      }
      return StatusState(statusRepo, areaState);
    },
  ),
  ChangeNotifierProvider(
    create: (context) => FilterPlate(context.read<PlateRepository>()),
  ),
  Provider(
    create: (context) => DeletePlate(context.read<PlateRepository>(), {}),
  ),
  Provider(
    create: (context) => MovementPlate(context.read<PlateRepository>()),
  ),
];
