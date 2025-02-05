import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'repositories/plate_repository.dart'; // PlateRepository 가져오기
import 'repositories/location_repository.dart'; // LocationRepository 가져오기
import 'repositories/user_repository.dart'; // UserRepository 가져오기
import 'repositories/adjustment_repository.dart'; // AdjustmentRepository 가져오기
import 'repositories/status_repository.dart'; // 🔄 StatusRepository 가져오기
import 'states/secondary_access_state.dart';
import 'states/page_state.dart';
import 'states/plate_state.dart';
import 'states/page_info.dart';
import 'states/area_state.dart'; // 🔄 AreaState 가져오기
import 'states/user_state.dart';
import 'states/location_state.dart';
import 'states/adjustment_state.dart';
import 'states/status_state.dart'; // 🔄 Firestore 연동된 StatusState 가져오기

// 상태 관리 객체 초기화
final List<SingleChildWidget> appProviders = [
  Provider<PlateRepository>(create: (_) => FirestorePlateRepository()),
  Provider<UserRepository>(create: (_) => FirestoreUserRepository()),
  Provider<AdjustmentRepository>(create: (_) => FirestoreAdjustmentRepository()),
  Provider<StatusRepository>(create: (_) => StatusRepository()),
  ChangeNotifierProvider(create: (context) => PageState(pages: defaultPages)),
  ChangeNotifierProvider(
    create: (context) => PlateState(context.read<PlateRepository>()),
  ),
  ChangeNotifierProvider(create: (_) => AreaState()),
  ChangeNotifierProvider(
    create: (context) => UserState(context.read<UserRepository>()),
  ),
  ChangeNotifierProvider(create: (_) => SecondaryAccessState()),
  ChangeNotifierProvider(
    create: (context) => LocationState(FirestoreLocationRepository()),
  ),
  ChangeNotifierProvider(
    create: (context) => AdjustmentState(
      context.read<AdjustmentRepository>(),
      context.read<AreaState>(),
    ),
  ),
  ChangeNotifierProvider(
    create: (context) {
      final statusRepo = context.read<StatusRepository?>();
      if (statusRepo == null) {
        throw Exception("StatusRepository가 등록되지 않았습니다.");
      }
      return StatusState(statusRepo, context.read<AreaState>());
    },
  ),
];
