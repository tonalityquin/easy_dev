import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../repositories/firestore_location_repository.dart';
import '../repositories/firestore_status_repository.dart';
import '../states/secondary_access_state.dart';
import '../states/page_state.dart';
import '../states/plate_state.dart';
import '../states/page_info.dart';
import '../states/area_state.dart';
import '../states/user_state.dart';
import '../states/location_state.dart';
import '../states/adjustment_state.dart';
import '../states/status_state.dart';
import '../repositories/adjustment_repository.dart';
import '../repositories/status_repository.dart';
import '../repositories/plate_repository.dart';
import '../repositories/user_repository.dart';

final List<SingleChildWidget> stateProviders = [
  ChangeNotifierProvider(create: (context) => PageState(pages: defaultPages)),
  ChangeNotifierProvider(create: (_) => AreaState()),
  ChangeNotifierProvider(create: (context) => SecondaryAccessState()),
  ChangeNotifierProvider(
    create: (context) => PlateState(context.read<PlateRepository>()),
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
];
