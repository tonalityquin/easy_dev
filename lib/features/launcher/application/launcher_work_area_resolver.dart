import '../../account/domain/models/user/user_model.dart';
import '../../headquarter/application/area/area_master_cache.dart';
import 'app_mode_definition.dart';
import 'app_mode_registry.dart';
import 'launcher_diagnostics.dart';
import 'launcher_work_area_option.dart';

class LauncherWorkAreaResolver {
  const LauncherWorkAreaResolver._();

  static Future<LauncherWorkAreaResolution> resolve({
    required UserModel user,
    required List<AppModeDefinition> accountModes,
  }) async {
    final divisions = user.divisions
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final homeCompany = user.companyId.trim();
    final ordered = <String>[
      if (homeCompany.isNotEmpty && divisions.contains(homeCompany)) homeCompany,
      ...divisions.where((value) => value != homeCompany),
    ];
    if (ordered.isEmpty) {
      return const LauncherWorkAreaResolution(
        hasSnapshot: false,
        division: '',
        areas: <LauncherWorkAreaOption>[],
        dataSource: 'none',
      );
    }

    final allowedAreaNames = user.areas.map((value) => value.trim()).toSet();
    final allowedIds = user.areaIds.map((value) => value.trim()).toSet();
    final accountModeIds = accountModes.map((mode) => mode.id).toSet();
    final areas = <LauncherWorkAreaOption>[];
    var complete = true;
    for (final division in ordered) {
      final snapshot = await AreaMasterCache.readSnapshot(division);
      if (snapshot == null) {
        complete = false;
        continue;
      }
      for (final item in snapshot.items) {
        if (!allowedAreaNames.contains(item.name.trim())) continue;
        if (allowedIds.isNotEmpty &&
            !allowedIds.contains('$division-${item.name.trim()}')) continue;
        final modes = AppModeRegistry.supportedModes(
          item.modes,
          allowedIds: accountModeIds,
        );
        if (!item.isHeadquarter && modes.isEmpty) continue;
        areas.add(LauncherWorkAreaOption(
          division: division,
          areaName: item.name.trim(),
          isHeadquarter: item.isHeadquarter,
          supportedModes: List<AppModeDefinition>.unmodifiable(modes),
          dataSource: 'sqlite',
        ));
      }
    }

    areas.sort((a, b) {
      if (a.isHeadquarter != b.isHeadquarter) {
        return a.isHeadquarter ? -1 : 1;
      }
      return a.areaName.toLowerCase().compareTo(b.areaName.toLowerCase());
    });

    LauncherDiagnostics.record(
      'auth_work_areas_ready',
      meta: <String, Object?>{
        'division': homeCompany,
        'authorizedCompanyCount': ordered.length,
        'areaCount': areas.length,
        'allCompanySnapshotsLoaded': complete,
        'firebaseReads': 0,
        'firebaseWrites': 0,
        'dataSource': 'sqlite',
      },
    );

    return LauncherWorkAreaResolution(
      hasSnapshot: complete,
      division: homeCompany,
      areas: List<LauncherWorkAreaOption>.unmodifiable(areas),
      dataSource: 'sqlite',
    );
  }
}
