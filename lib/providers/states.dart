import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

// 📦 Repositories
import '../repositories/adjustment/adjustment_repository.dart';
import '../repositories/location/firestore_location_repository.dart';
import '../repositories/plate/plate_repository.dart';
import '../repositories/status/firestore_status_repository.dart';
import '../repositories/status/status_repository.dart';
import '../repositories/user/user_repository.dart';

// 📦 States
import '../states/area/area_state.dart';
import '../states/calendar/selected_date_store.dart';
import '../states/page/page_info.dart';
import '../states/page/page_state.dart';
import '../states/plate/log_plate.dart';
import '../states/plate/modify_plate.dart';
import '../states/user/user_state.dart';
import '../states/location/location_state.dart';
import '../states/adjustment/adjustment_state.dart';
import '../states/status/status_state.dart';
import '../states/plate/input_plate.dart';
import '../states/plate/plate_state.dart';
import '../states/plate/filter_plate.dart';
import '../states/plate/delete_plate.dart';
import '../states/plate/movement_plate.dart';
import '../states/secondary/secondary_mode.dart';
import '../states/calendar/field_selected_date_state.dart';

final List<SingleChildWidget> stateProviders = [
  // 🌐 전역 페이지 상태
  ChangeNotifierProvider(
    create: (context) => PageState(pages: defaultPages),
  ),

  // 📍 현재 선택된 지역
  ChangeNotifierProvider(
    create: (_) => AreaState(),
  ),

  // 🧭 서브 페이지 모드 (현장/사무실/통계)
  ChangeNotifierProvider(
    create: (_) => SecondaryMode(),
  ),

  // ✅ 로그 기록 상태 (GCS 업로드용 내부 구현 사용)
  ChangeNotifierProvider(
    create: (_) => LogPlateState(),
  ),

  // 🔧 차량 정보 수정 상태
  ChangeNotifierProvider(
    create: (context) => ModifyPlate(
      context.read<PlateRepository>(),
    ),
  ),

  // 🚘 차량 입차 처리 상태
  ChangeNotifierProvider(
    create: (context) => InputPlate(
      context.read<PlateRepository>(),
      context.read<LogPlateState>(),
    ),
  ),

  // 🚘 차량 데이터 실시간 동기화
  ChangeNotifierProvider(
    create: (context) {
      final repo = context.read<PlateRepository>();
      final area = context.read<AreaState>();
      return PlateState(repo, area);
    },
  ),

  // 🔍 차량 검색 필터 상태
  ChangeNotifierProvider(
    create: (context) => FilterPlate(context.read<PlateRepository>()),
  ),

  // ❌ 삭제 로직 담당
  Provider(
    create: (context) => DeletePlate(
      context.read<PlateRepository>(),
      {},
    ),
  ),

  // 🔄 상태 간 Plate 이동 처리 (✅ 로그 기록 포함)
  Provider(
    create: (context) => MovementPlate(
      context.read<PlateRepository>(),
      context.read<LogPlateState>(), // ✅ 로그 상태 주입
    ),
  ),

  // 👤 사용자 정보 관리 상태
  ChangeNotifierProvider(
    create: (context) => UserState(context.read<UserRepository>()),
  ),

  // 📍 위치 관리 상태
  ChangeNotifierProvider(
    create: (context) => LocationState(FirestoreLocationRepository()),
  ),

  // 💸 정산 기준 상태
  ChangeNotifierProvider(
    create: (context) {
      final repo = context.read<AdjustmentRepository>();
      final area = context.read<AreaState>();
      return AdjustmentState(repo, area);
    },
  ),

  // 📊 사용자 정의 상태 관리
  ChangeNotifierProvider(
    create: (context) {
      final repo = context.read<StatusRepository?>() ?? FirestoreStatusRepository();
      final area = context.read<AreaState>();
      return StatusState(repo, area);
    },
  ),

  // 📅 선택된 날짜 상태
  ChangeNotifierProvider(
    create: (_) => FieldSelectedDateState(),
  ),

  // 📊 통계 달력에서 사용하는 선택된 날짜 상태
  ChangeNotifierProvider(
    create: (_) => SelectedDateStore(),
  ),
];
