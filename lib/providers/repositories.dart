import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../repositories/adjustment/firestore_adjustment_repository.dart';
import '../repositories/location/firestore_location_repository.dart';
import '../repositories/plate/firestore_plate_repository.dart';
import '../repositories/status/firestore_status_repository.dart';
import '../repositories/user/firestore_user_repository.dart';
import '../repositories/plate/plate_repository.dart';
import '../repositories/location/location_repository.dart';
import '../repositories/user/user_repository.dart';
import '../repositories/adjustment/adjustment_repository.dart';
import '../repositories/status/status_repository.dart';

final List<SingleChildWidget> repositoryProviders = [
  Provider<PlateRepository>(create: (_) => FirestorePlateRepository()),
  Provider<LocationRepository>(create: (_) => FirestoreLocationRepository()),
  Provider<UserRepository>(create: (_) => FirestoreUserRepository()),
  Provider<AdjustmentRepository>(create: (_) => FirestoreAdjustmentRepository()),
  Provider<StatusRepository>(create: (_) => FirestoreStatusRepository()),
];
