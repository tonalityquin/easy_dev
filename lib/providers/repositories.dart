import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../repositories/bill_repo_services/firestore_bill_repository.dart';
import '../repositories/location_repo_services/firestore_location_repository.dart';
import '../repositories/plate_repo_services/firestore_plate_repository.dart';
import '../repositories/user_repo_services/firestore_user_repository.dart';

import '../repositories/plate_repo_services/plate_repository.dart';
import '../repositories/location_repo_services/location_repository.dart';
import '../repositories/user_repo_services/user_repository.dart';
import '../repositories/bill_repo_services/bill_repository.dart';

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
  Provider<BillRepository>(
    create: (_) {
      return FirestoreBillRepository();
    },
  ),
];
