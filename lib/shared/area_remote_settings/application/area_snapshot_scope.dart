import '../../../features/headquarter/application/snapshot/headquarter_snapshot_repository.dart';
import '../../../features/headquarter/domain/models/headquarter_download_snapshot.dart';

class AreaSnapshotScope {
  AreaSnapshotScope._();

  static String _division = '';
  static String _area = '';

  static String get division => _division;
  static String get area => _area;
  static bool get isBound => _division.isNotEmpty && _area.isNotEmpty;

  static void bind({required String division, required String area}) {
    _division = division.trim();
    _area = area.trim();
  }

  static void clear() {
    _division = '';
    _area = '';
  }

  static Future<HeadquarterSnapshotArea?> readCurrentArea() async {
    if (!isBound) return null;
    return HeadquarterSnapshotRepository.instance.readArea(
      division: _division,
      area: _area,
    );
  }
}
