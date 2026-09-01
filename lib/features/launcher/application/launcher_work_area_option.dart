import '../../dev/domain/repositories/area_repo_package/area_repository.dart';
import 'app_mode_definition.dart';

class LauncherWorkAreaOption {
  const LauncherWorkAreaOption({
    required this.division,
    required this.areaName,
    required this.isHeadquarter,
    required this.supportedModes,
    this.requiresServerHeadquarterVerification = false,
    this.verifiedAreaRecord,
    this.dataSource = 'sqlite',
  });

  final String division;
  final String areaName;
  final bool isHeadquarter;
  final List<AppModeDefinition> supportedModes;
  final bool requiresServerHeadquarterVerification;
  final AreaRecord? verifiedAreaRecord;
  final String dataSource;

  bool get hasVerifiedAreaRecord => verifiedAreaRecord != null;
  String get displayLabel => isHeadquarter ? '본사' : areaName;
}

class LauncherWorkAreaResolution {
  const LauncherWorkAreaResolution({
    required this.hasSnapshot,
    required this.division,
    required this.areas,
    this.dataSource = 'none',
    this.firebaseAreaDocumentReads = 0,
    this.serverFallbackUsed = false,
    this.headquarterFastPath = false,
  });

  final bool hasSnapshot;
  final String division;
  final List<LauncherWorkAreaOption> areas;
  final String dataSource;
  final int firebaseAreaDocumentReads;
  final bool serverFallbackUsed;
  final bool headquarterFastPath;
}
