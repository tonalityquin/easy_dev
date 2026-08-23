import '../../../../app/models/capability.dart';

class HeadquarterSnapshotArea {
  const HeadquarterSnapshotArea({
    required this.division,
    required this.name,
    required this.email,
    required this.invite,
    required this.communication,
    required this.modes,
    required this.capabilities,
    required this.isHeadquarter,
  });

  final String division;
  final String name;
  final String email;
  final String invite;
  final String communication;
  final Set<String> modes;
  final CapSet capabilities;
  final bool isHeadquarter;

  bool supportsMode(String modeKey) =>
      modes.contains(modeKey.trim().toLowerCase());

  bool supportsCapability(Capability capability) =>
      capabilities.contains(capability);
}

class HeadquarterDownloadSnapshot {
  const HeadquarterDownloadSnapshot({
    required this.division,
    required this.downloadedAtIso,
    required this.areas,
  });

  final String division;
  final String downloadedAtIso;
  final List<HeadquarterSnapshotArea> areas;

  int get branchCount => areas.where((area) => !area.isHeadquarter).length;

  int supportCount(String modeKey) {
    final normalized = modeKey.trim().toLowerCase();
    if (normalized.isEmpty) return 0;
    return areas
        .where((area) => !area.isHeadquarter && area.supportsMode(normalized))
        .length;
  }

  int capabilityCount(Capability capability) {
    return areas
        .where(
          (area) =>
              !area.isHeadquarter && area.supportsCapability(capability),
        )
        .length;
  }
}

class HeadquarterSnapshotDiagnostics {
  const HeadquarterSnapshotDiagnostics({
    required this.databaseVersion,
    required this.division,
    required this.downloadedAtIso,
    required this.areaCount,
    required this.singleCount,
    required this.doubleCount,
    required this.tripleCount,
    required this.minorCount,
    required this.tabletCount,
  });

  final int databaseVersion;
  final String division;
  final String downloadedAtIso;
  final int areaCount;
  final int singleCount;
  final int doubleCount;
  final int tripleCount;
  final int minorCount;
  final int tabletCount;
}
