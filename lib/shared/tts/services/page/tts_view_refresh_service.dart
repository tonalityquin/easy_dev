
import '../../../plate/data/repositories/firestore_plate_repository.dart';
import '../../../plate/domain/repositories/plate_repository.dart';

class TtsViewRefreshService {
  static PlateRepository _repository = FirestorePlateRepository();

  static const String _colReq = 'parking_requests_view';
  static const String _colPc = 'parking_completed_view';
  static const String _colDep = 'departure_requests_view';

  static void configureRepository(PlateRepository repository) {
    _repository = repository;
  }

  static Duration _cooldownForCollection(String collection) {
    if (collection == _colPc) return const Duration(seconds: 15);
    return const Duration(seconds: 3);
  }

  static String _k(String collection, String area) =>
      '$collection|${area.trim()}';

  static final Map<String, DateTime> _blockedUntilByKey = <String, DateTime>{};
  static final Map<String, Map<String, dynamic>?> _lastDataByKey =
      <String, Map<String, dynamic>?>{};

  static bool _isBlocked(String collection, String area) {
    final k = _k(collection, area);
    final until = _blockedUntilByKey[k];
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  static void _startCooldown(String collection, String area) {
    final a = area.trim();
    if (a.isEmpty) return;
    final k = _k(collection, a);
    _blockedUntilByKey[k] =
        DateTime.now().add(_cooldownForCollection(collection));
  }

  static Future<void> _fetchOne(
    String collection,
    String area, {
    required bool force,
  }) async {
    final a = area.trim();
    if (a.isEmpty) return;

    if (!force) {
      if (_isBlocked(collection, a)) return;
      _startCooldown(collection, a);
    }

    final data = await _repository.fetchViewDocumentData(
      collection: collection,
      area: a,
    );
    _lastDataByKey[_k(collection, a)] = data;
  }

  static Future<void> refreshFull(String area) async {
    final a = area.trim();
    if (a.isEmpty) return;
    await Future.wait<void>(<Future<void>>[
      _fetchOne(_colReq, a, force: true),
      _fetchOne(_colPc, a, force: true),
      _fetchOne(_colDep, a, force: true),
    ]);
  }

  static Future<void> refreshDepartureOnly(String area) async {
    final a = area.trim();
    if (a.isEmpty) return;
    await _fetchOne(_colDep, a, force: false);
  }
}
