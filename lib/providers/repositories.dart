import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../repositories/bill_repo/firestore_bill_repository.dart';
import '../repositories/location/firestore_location_repository.dart';
import '../repositories/plate/firestore_plate_repository.dart';
import '../repositories/user/firestore_user_repository.dart';

import '../repositories/plate/plate_repository.dart';
import '../repositories/location/location_repository.dart';
import '../repositories/user/user_repository.dart';
import '../repositories/bill_repo/bill_repository.dart';

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
