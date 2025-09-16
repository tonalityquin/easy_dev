// (예시 경로) lib/state_providers.dart
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

  // ▼▼▼ 여기부터 SecondaryState 전역 주입 (UserState, AreaState 이후여야 함) ▼▼▼
  ChangeNotifierProxyProvider2<UserState, AreaState, SecondaryState>(
    create: (_) => SecondaryState(pages: const [tabLocalData, tabBackend]),
    update: (ctx, userState, areaState, secondaryState) {
      // role/caps 기반 탭 계산
      final role = RoleType.fromName(userState.role);
      final caps = areaState.capabilitiesOfCurrentArea;

      List<SecondaryInfo> computePages(RoleType role, CapSet areaCaps) {
        final allowedSections = kRolePolicy[role] ?? const <Section>{};
        if (allowedSections.isEmpty) {
          // 방어적으로 공통 최소 탭 제공
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
        // 혹시 전부 필터링되어 비면 공통 최소 탭 제공
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
