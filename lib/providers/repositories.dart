import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../repositories/firestore_adjustment_repository.dart';
import '../repositories/firestore_location_repository.dart';
import '../repositories/firestore_plate_repository.dart';
import '../repositories/firestore_status_repository.dart';
import '../repositories/firestore_user_repository.dart';
import '../repositories/plate_repository.dart';
import '../repositories/location_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/adjustment_repository.dart';
import '../repositories/status_repository.dart';

final List<SingleChildWidget> repositoryProviders = [
  Provider<PlateRepository>(create: (_) => FirestorePlateRepository()),
  Provider<LocationRepository>(create: (_) => FirestoreLocationRepository()),
  Provider<UserRepository>(create: (_) => FirestoreUserRepository()),
  Provider<AdjustmentRepository>(create: (_) => FirestoreAdjustmentRepository()),
  Provider<StatusRepository>(create: (_) => FirestoreStatusRepository()),
];
