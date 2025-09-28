import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../repositories/bill_repo_services/bill_repository.dart';
import '../repositories/location_repo_services/firestore_location_repository.dart';
import '../repositories/plate_repo_services/plate_repository.dart';
import '../repositories/user_repo_services/user_repository.dart';

// 🔽 추가: write 트랜잭션 서비스 DI
import '../repositories/plate_repo_services/plate_write_service.dart';

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
// ⛔️ 리팩터링 후 불필요 → 삭제
// import '../states/plate/input_log_plate.dart';
import '../states/plate/modify_plate.dart';
import '../states/plate/input_plate.dart';
import '../states/plate/plate_state.dart';
import '../states/plate/filter_plate.dart';
import '../states/plate/delete_plate.dart';
import '../states/plate/movement_plate.dart';
import '../states/user/user_state.dart';

// ▼ Secondary 탭 계산에 필요한 것들
import '../states/secondary/secondary_state.dart';
import '../states/secondary/secondary_info.dart';
import '../models/capability.dart';

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

  // ⛔️ 리팩터링(로그 병합)으로 InputLogPlate를 더 이상 주입/사용하지 않습니다.
  // ChangeNotifierProvider(
  //   create: (_) => InputLogPlate(),
  // ),

  ChangeNotifierProvider(
    create: (context) => ModifyPlate(
      context.read<PlateRepository>(),
    ),
  ),

  // ✅ InputPlate는 PlateRepository 하나만 받습니다.
  ChangeNotifierProvider(
    create: (context) => InputPlate(
      context.read<PlateRepository>(),
    ),
  ),

  // ✅ PlateState는 기존처럼 PlateRepository + AreaState
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

  // ⚠️ 순서 중요: MovementPlate가 UserState와 PlateWriteService를 읽어야 하므로
  // UserState, PlateWriteService를 먼저 등록한다.

  // ✅ UserState (앞당김)
  ChangeNotifierProvider(
    create: (context) => UserState(
      context.read<UserRepository>(),
      context.read<AreaState>(),
    ),
  ),

  // ✅ PlateWriteService DI (신규)
  Provider(
    create: (_) => PlateWriteService(),
  ),

  // ✅ MovementPlate는 (PlateWriteService, UserState)를 받도록 변경됨
  ChangeNotifierProvider(
    create: (context) => MovementPlate(
      context.read<PlateWriteService>(),
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
  // ▼ 개발용 Dev 캘린더 모델
  ChangeNotifierProvider(
    create: (_) => DevCalendarModel(DevGoogleCalendarService()),
  ),

  // ▼▼▼ SecondaryState 전역 주입 ▼▼▼
  ChangeNotifierProxyProvider2<UserState, AreaState, SecondaryState>(
    create: (_) => SecondaryState(pages: const [tabLocalData, tabBackend]),
    update: (ctx, userState, areaState, secondaryState) {
      final role = RoleType.fromName(userState.role);
      final caps = areaState.capabilitiesOfCurrentArea;

      List<SecondaryInfo> computePages(RoleType role, CapSet areaCaps) {
        final allowedSections = kRolePolicy[role] ?? const <Section>{};
        if (allowedSections.isEmpty) {
          return const [tabLocalData, tabBackend];
        }
        final pages = <SecondaryInfo>[];
        for (final section in allowedSections) {
          final need = kSectionRequires[section] ?? const <Capability>{};
          if (Cap.supports(areaCaps, need)) {
            final info = kSectionTab[section];
            if (info != null) pages.add(info);
          }
        }
        return pages.isEmpty ? const [tabLocalData, tabBackend] : pages;
      }

      bool sameByTitle(List<SecondaryInfo> a, List<SecondaryInfo> b) {
        if (identical(a, b)) return true;
        if (a.length != b.length) return false;
        for (int i = 0; i < a.length; i++) {
          if (a[i].title != b[i].title) return false;
        }
        return true;
      }

      final state =
          secondaryState ?? SecondaryState(pages: const [tabLocalData, tabBackend]);
      final newPages = computePages(role, caps);

      if (!sameByTitle(state.pages, newPages)) {
        state.updatePages(newPages, keepIndex: true);
      }
      return state;
    },
  ),
];
