import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../repositories/firestore_plate_repository.dart';
import '../repositories/plate_repository.dart';
import '../repositories/location_repository.dart';  // ✅ 다시 추가 (사용된다면)
import '../repositories/user_repository.dart';
import '../repositories/adjustment_repository.dart';
import '../repositories/status_repository.dart';

// Repository Providers 정의
final List<SingleChildWidget> repositoryProviders = [
  Provider<PlateRepository>(create: (_) => FirestorePlateRepository()),
  Provider<LocationRepository>(create: (_) => FirestoreLocationRepository()), // ✅ 필요하면 추가
  Provider<UserRepository>(create: (_) => FirestoreUserRepository()),
  Provider<AdjustmentRepository>(create: (_) => FirestoreAdjustmentRepository()),
  Provider<StatusRepository>(create: (_) => StatusRepository()),
];
