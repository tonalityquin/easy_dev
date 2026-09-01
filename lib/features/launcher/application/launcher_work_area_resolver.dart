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
    final division = user.divisions.firstOrNull?.trim() ?? '';
    if (division.isEmpty) {
      LauncherDiagnostics.record(
        'auth_work_areas_unavailable',
        meta: const <String, Object?>{
          'reason': 'division_empty',
          'firebaseReads': 0,
          'firebaseWrites': 0,
          'dataSource': 'none',
        },
      );
      return const LauncherWorkAreaResolution(
        hasSnapshot: false,
        division: '',
        areas: <LauncherWorkAreaOption>[],
        dataSource: 'none',
      );
    }

    final snapshot = await AreaMasterCache.readSnapshot(division);
    if (snapshot == null) {
      LauncherDiagnostics.record(
        'auth_work_areas_snapshot_missing',
        meta: <String, Object?>{
          'division': division,
          'authorizedAreaCount': user.areas
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .length,
          'firebaseReads': 0,
          'firebaseWrites': 0,
          'dataSource': 'sqlite_miss',
        },
      );
      return LauncherWorkAreaResolution(
        hasSnapshot: false,
        division: division,
        areas: const <LauncherWorkAreaOption>[],
        dataSource: 'sqlite_miss',
      );
    }

    final allowedAreaNames = user.areas
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final accountModeIds = accountModes.map((mode) => mode.id).toSet();
    final areas = <LauncherWorkAreaOption>[];

    for (final item in snapshot.items) {
      if (!allowedAreaNames.contains(item.name.trim())) continue;
      final modes = AppModeRegistry.supportedModes(
        item.modes,
        allowedIds: accountModeIds,
      );
      if (!item.isHeadquarter && modes.isEmpty) continue;
      areas.add(
        LauncherWorkAreaOption(
          division: division,
          areaName: item.name.trim(),
          isHeadquarter: item.isHeadquarter,
          supportedModes: List<AppModeDefinition>.unmodifiable(modes),
          dataSource: 'sqlite',
        ),
      );
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
        'division': division,
        'areaCount': areas.length,
        'headquarterCount': areas.where((area) => area.isHeadquarter).length,
        'areas': areas
            .map(
              (area) =>
                  '${area.areaName}:${area.isHeadquarter ? 'hq' : 'field'}:${area.supportedModes.map((mode) => mode.id).join('+')}',
            )
            .join(','),
        'firebaseReads': 0,
        'firebaseWrites': 0,
        'dataSource': 'sqlite',
      },
    );

    return LauncherWorkAreaResolution(
      hasSnapshot: true,
      division: division,
      areas: List<LauncherWorkAreaOption>.unmodifiable(areas),
      dataSource: 'sqlite',
    );
  }
}
