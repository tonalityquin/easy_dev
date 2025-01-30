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
  Provider<StatusRepository>(create: (_) => StatusRepository()), // 🔄 FirestoreStatusRepository 추가
  ChangeNotifierProvider(create: (_) => PageState(pages: defaultPages)),
  ChangeNotifierProvider(create: (_) => PlateState(FirestorePlateRepository())),
  ChangeNotifierProvider(create: (_) => AreaState()), // 🔄 AreaState 추가
  ChangeNotifierProvider(create: (_) => UserState(FirestoreUserRepository())),
  ChangeNotifierProvider(create: (_) => SecondaryAccessState()),
  ChangeNotifierProvider(create: (_) => LocationState(FirestoreLocationRepository())),
  ChangeNotifierProvider(
    create: (context) => AdjustmentState(
      context.read<AdjustmentRepository>(),
      context.read<AreaState>(),
    ),
  ),
  ChangeNotifierProvider(
    create: (context) => StatusState(
      context.read<StatusRepository>(), // 🔄 Firestore에서 데이터 가져오기
      context.read<AreaState>(), // 🔄 AreaState 주입 (지역 변경 감지)
    ),
  ),
];
