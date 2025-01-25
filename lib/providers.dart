import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'repositories/plate_repository.dart'; // PlateRepository 가져오기
import 'repositories/location_repository.dart'; // LocationRepository 가져오기
import 'repositories/user_repository.dart'; // UserRepository 가져오기
import 'repositories/adjustment_repository.dart'; // AdjustmentRepository 가져오기
import 'states/secondary_access_state.dart'; // SecondaryAccess 상태 관리
import 'states/page_state.dart'; // 페이지 상태 관리를 위한 상태 클래스
import 'states/plate_state.dart'; // 차량 관련 데이터를 관리하는 상태 클래스
import 'states/page_info.dart'; // 페이지 정보 (기본 페이지 리스트 포함)
import 'states/area_state.dart'; // 지역 상태 관리
import 'states/user_state.dart'; // 사용자 상태 관리
import 'states/location_state.dart'; // Location 상태 관리
import 'states/adjustment_state.dart'; // AdjustmentState 가져오기

// 상태 관리 객체 초기화
final List<SingleChildWidget> appProviders = [
  // Firestore 기반의 Repository 구현체 생성
  Provider<PlateRepository>(
    create: (_) => FirestorePlateRepository(),
  ),
  Provider<UserRepository>(
    create: (_) => FirestoreUserRepository(), // UserRepository 주입
  ),
  Provider<AdjustmentRepository>(
    create: (_) => FirestoreAdjustmentRepository(), // AdjustmentRepository 주입
  ),
  ChangeNotifierProvider(
    create: (_) => PageState(pages: defaultPages),
  ),
  ChangeNotifierProvider(
    create: (_) => PlateState(FirestorePlateRepository()), // PlateRepository 주입
  ),
  ChangeNotifierProvider(
    create: (_) => AreaState(), // AreaState 생성
  ),
  ChangeNotifierProvider(
    create: (_) => UserState(FirestoreUserRepository()), // UserState에 UserRepository 주입
  ),
  ChangeNotifierProvider(
    create: (_) => SecondaryAccessState(),
  ),
  ChangeNotifierProvider(
    create: (_) => LocationState(FirestoreLocationRepository()), // LocationRepository 주입
  ),
  ChangeNotifierProvider(
    create: (context) => AdjustmentState(
      context.read<AdjustmentRepository>(), // AdjustmentRepository 주입
      context.read<AreaState>(), // AreaState 주입
    ),
  ),
];
