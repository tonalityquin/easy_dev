import '../../data/local/headquarter_snapshot_database.dart';
import '../../domain/models/headquarter_download_snapshot.dart';

class HeadquarterSnapshotRepository {
  HeadquarterSnapshotRepository._();

  static final HeadquarterSnapshotRepository instance =
      HeadquarterSnapshotRepository._();

  Future<HeadquarterDownloadSnapshot?> readSnapshot(String division) {
    return HeadquarterSnapshotDatabase.instance.readSnapshot(division);
  }

  Future<HeadquarterSnapshotArea?> readArea({
    required String division,
    required String area,
  }) {
    return HeadquarterSnapshotDatabase.instance.readArea(
      division: division,
      area: area,
    );
  }

  Future<HeadquarterSnapshotDiagnostics?> readDiagnostics(String division) {
    return HeadquarterSnapshotDatabase.instance.readDiagnostics(division);
  }
}
