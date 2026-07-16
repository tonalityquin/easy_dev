import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../features/account/data/repositories/firestore_user_repository.dart';
import '../../features/calendar/data/repositories/in_memory_headquarter_calendar_repository.dart';
import '../../features/calendar/domain/repositories/headquarter_calendar_repository.dart';
import '../../features/account/domain/repositories/user_repository.dart';
import '../../features/dev/data/repositories/area_repo_package/firestore_area_repository.dart';
import '../../features/dev/domain/repositories/area_repo_package/area_repository.dart';
import '../../features/location/data/repositories/firestore_location_repository.dart';
import '../../features/location/domain/repositories/location_repository.dart';
import '../../features/payment/data/repositories/firestore_bill_repository.dart';
import '../../features/payment/domain/repositories/bill_repository.dart';
import '../../shared/plate/data/repositories/firestore_plate_repository.dart';
import '../../shared/plate/domain/repositories/plate_repository.dart';

final List<SingleChildWidget> repositoryProviders = [
  Provider<PlateRepository>(
    create: (_) {
      return FirestorePlateRepository();
    },
  ),
  Provider<LocationRepository>(
    create: (_) {
      return FirestoreLocationRepository();
    },
  ),
  Provider<UserRepository>(
    create: (_) {
      return FirestoreUserRepository();
    },
  ),
  Provider<HeadquarterCalendarRepository>(
    create: (_) {
      return InMemoryHeadquarterCalendarRepository();
    },
    dispose: (_, repository) {
      if (repository is InMemoryHeadquarterCalendarRepository) {
        repository.dispose();
      }
    },
  ),
  Provider<AreaRepository>(
    create: (_) {
      return FirestoreAreaRepository();
    },
  ),
  Provider<BillRepository>(
    create: (_) {
      return FirestoreBillRepository();
    },
  ),
];
