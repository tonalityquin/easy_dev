import '../../../../app/models/capability.dart';
import '../../../../app/models/account_area_access.dart';
import '../../../dev/data/repositories/area_repo_package/firestore_area_repository.dart';
import '../../domain/models/headquarter_download_snapshot.dart';
import '../snapshot/headquarter_snapshot_download_service.dart';
import '../snapshot/headquarter_snapshot_repository.dart';

class AreaMasterItem {
  final String name;
  final List<String> modes;
  final bool isHeadquarter;
  final CapSet capabilities;
  final String email;
  final String invite;
  final String communication;

  const AreaMasterItem({
    required this.name,
    required this.modes,
    required this.isHeadquarter,
    required this.capabilities,
    this.email = '',
    this.invite = '',
    this.communication = '',
  });
}

class AreaMasterSnapshot {
  final String division;
  final List<AreaMasterItem> items;
  final String refreshedAtIso;

  const AreaMasterSnapshot({
    required this.division,
    required this.items,
    required this.refreshedAtIso,
  });
}

class AreaMasterSelectableData {
  const AreaMasterSelectableData({
    required this.hasCache,
    required this.selectableAreas,
    required this.isHeadquarterByName,
    this.visibleAreas = const <String>[],
    this.modeSupportedAreas = const <String>{},
    this.assignedAreas = const <String>{},
    this.headquarterAllowed = true,
  });

  final bool hasCache;
  final List<String> selectableAreas;
  final Map<String, bool> isHeadquarterByName;
  final List<String> visibleAreas;
  final Set<String> modeSupportedAreas;
  final Set<String> assignedAreas;
  final bool headquarterAllowed;

  String rejectionReason(String area) {
    if (!assignedAreas.contains(area)) {
      return AccountAreaAccess.notAssigned;
    }
    if (isHeadquarterByName[area] == true && !headquarterAllowed) {
      return AccountAreaAccess.headquarterUnavailable;
    }
    if (!selectableAreas.contains(area)) {
      return AccountAreaAccess.modeUnavailable;
    }
    return '';
  }
}

class AreaMasterCache {
  const AreaMasterCache._();

  static final HeadquarterSnapshotDownloadService _downloadService =
      HeadquarterSnapshotDownloadService();
  static final FirestoreAreaRepository _repository = FirestoreAreaRepository();
  static final Map<String, Future<AreaMasterSnapshot>> _activeRefreshes =
      <String, Future<AreaMasterSnapshot>>{};

  static Future<AreaMasterSnapshot?> readSnapshot(String division) async {
    final normalizedDivision = division.trim();
    if (normalizedDivision.isEmpty) return null;
    final snapshot = await HeadquarterSnapshotRepository.instance
        .readSnapshot(normalizedDivision);
    if (snapshot == null) return null;
    return _toAreaMasterSnapshot(snapshot);
  }

  static Future<HeadquarterDownloadSnapshot?> readDownloadedSnapshot(
    String division,
  ) {
    return HeadquarterSnapshotRepository.instance.readSnapshot(division);
  }

  static Future<AreaMasterSnapshot> refreshDivision(
    String division, {
    String requiredArea = '',
    HeadquarterSnapshotDownloadLog? onLog,
    double progressStart = 0,
    double progressEnd = 1,
  }) async {
    final normalizedDivision = division.trim();
    if (normalizedDivision.isEmpty) {
      throw ArgumentError('division is empty');
    }

    final active = _activeRefreshes[normalizedDivision];
    if (active != null) return active;

    final future = _refreshDivisionInternal(
      normalizedDivision,
      requiredArea: requiredArea,
      onLog: onLog,
      progressStart: progressStart,
      progressEnd: progressEnd,
    );
    _activeRefreshes[normalizedDivision] = future;

    try {
      return await future;
    } finally {
      if (identical(_activeRefreshes[normalizedDivision], future)) {
        _activeRefreshes.remove(normalizedDivision);
      }
    }
  }

  static Future<AreaMasterSnapshot> _refreshDivisionInternal(
    String normalizedDivision, {
    required String requiredArea,
    HeadquarterSnapshotDownloadLog? onLog,
    required double progressStart,
    required double progressEnd,
  }) async {
    final snapshot = await _downloadService.download(
      areaRepository: _repository,
      division: normalizedDivision,
      requiredArea: requiredArea,
      onLog: onLog,
      progressStart: progressStart,
      progressEnd: progressEnd,
    );
    return _toAreaMasterSnapshot(snapshot);
  }

  static Future<String> readLastRefreshAt(String division) async {
    final snapshot = await HeadquarterSnapshotRepository.instance
        .readSnapshot(division.trim());
    return snapshot?.downloadedAtIso.trim() ?? '';
  }

  static Future<AreaMasterSelectableData> readSelectableAreas({
    required String division,
    required List<String> userAreas,
    required String modeKey,
    String role = '',
  }) async {
    final snapshot = await readSnapshot(division);
    if (snapshot == null) {
      return const AreaMasterSelectableData(
        hasCache: false,
        selectableAreas: <String>[],
        isHeadquarterByName: <String, bool>{},
      );
    }

    final normalizedMode = modeKey.trim().toLowerCase();
    final isHeadquarterByName = <String, bool>{
      for (final item in snapshot.items) item.name: item.isHeadquarter,
    };

    final assigned = userAreas.map((area) => area.trim()).toSet();
    final visibleAreas = snapshot.items
        .map((item) => item.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final modeSupported = snapshot.items
        .where((item) => item.modes.contains(normalizedMode))
        .map((item) => item.name.trim())
        .toSet();
    final headquarterAllowed = AccountAreaAccess.isHeadOfficeRole(role);
    final selectableAreas = visibleAreas
        .where((name) =>
            assigned.contains(name) &&
            modeSupported.contains(name) &&
            (isHeadquarterByName[name] != true ||
                (headquarterAllowed && name == division.trim())))
        .toList(growable: false);

    return AreaMasterSelectableData(
      hasCache: true,
      selectableAreas: selectableAreas,
      isHeadquarterByName: isHeadquarterByName,
      visibleAreas: visibleAreas,
      modeSupportedAreas: modeSupported,
      assignedAreas: assigned,
      headquarterAllowed: headquarterAllowed,
    );
  }

  static AreaMasterSnapshot _toAreaMasterSnapshot(
    HeadquarterDownloadSnapshot snapshot,
  ) {
    final items = snapshot.areas
        .map(
          (area) => AreaMasterItem(
            name: area.name,
            modes: area.modes.toList(growable: false)..sort(),
            isHeadquarter: area.isHeadquarter,
            capabilities: Set<Capability>.unmodifiable(area.capabilities),
            email: area.email,
            invite: area.invite,
            communication: area.communication,
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));

    return AreaMasterSnapshot(
      division: snapshot.division,
      items: List<AreaMasterItem>.unmodifiable(items),
      refreshedAtIso: snapshot.downloadedAtIso,
    );
  }
}
