import '../../account/domain/models/user/user_model.dart';
import '../../dev/domain/repositories/area_repo_package/area_repository.dart';
import 'app_mode_definition.dart';
import 'app_mode_registry.dart';
import 'launcher_diagnostics.dart';
import 'launcher_work_area_option.dart';

class LauncherWorkAreaServerResolver {
  const LauncherWorkAreaServerResolver._();

  static Future<LauncherWorkAreaResolution> resolve({
    required UserModel user,
    required List<AppModeDefinition> accountModes,
    required AreaRepository areaRepository,
  }) async {
    final division = user.divisions.firstOrNull?.trim() ?? '';
    final authorizedAreas = user.areas
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (division.isEmpty || authorizedAreas.isEmpty) {
      LauncherDiagnostics.record(
        'auth_work_area_direct_fetch_blocked',
        meta: <String, Object?>{
          'division': division,
          'authorizedAreaCount': authorizedAreas.length,
          'reason': division.isEmpty ? 'division_empty' : 'authorized_area_empty',
          'firebaseAreaDocumentReads': 0,
          'firebaseWrites': 0,
        },
      );
      return LauncherWorkAreaResolution(
        hasSnapshot: false,
        division: division,
        areas: const <LauncherWorkAreaOption>[],
        dataSource: 'server_unavailable',
        serverFallbackUsed: true,
      );
    }

    final accountModeIds = accountModes.map((mode) => mode.id).toSet();
    final fetched = <String, AreaRecord?>{};
    var readAttempts = 0;

    Future<AreaRecord?> fetchArea(String areaName, String phase) async {
      if (fetched.containsKey(areaName)) return fetched[areaName];
      readAttempts += 1;
      LauncherDiagnostics.record(
        'auth_work_area_direct_fetch_record_start',
        meta: <String, Object?>{
          'division': division,
          'area': areaName,
          'phase': phase,
          'documentId': '$division-$areaName',
          'firebaseAreaDocumentReadAttempt': readAttempts,
        },
      );
      try {
        final record = await areaRepository.getAreaByName(
          areaName,
          division: division,
          serverOnly: true,
        );
        fetched[areaName] = record;
        LauncherDiagnostics.record(
          record == null
              ? 'auth_work_area_direct_fetch_record_missing'
              : 'auth_work_area_direct_fetch_record_success',
          meta: <String, Object?>{
            'division': division,
            'area': areaName,
            'phase': phase,
            'documentId': '$division-$areaName',
            'isHeadquarter': record?.isHeadquarter,
            'modes': record?.modes.join(',') ?? '',
            'firebaseAreaDocumentReads': readAttempts,
          },
        );
        return record;
      } catch (error, stackTrace) {
        fetched[areaName] = null;
        LauncherDiagnostics.record(
          'auth_work_area_direct_fetch_record_error',
          meta: <String, Object?>{
            'division': division,
            'area': areaName,
            'phase': phase,
            'documentId': '$division-$areaName',
            'firebaseAreaDocumentReads': readAttempts,
            'error': error,
            'stack': stackTrace,
          },
        );
        return null;
      }
    }

    LauncherDiagnostics.record(
      'auth_work_area_direct_fetch_start',
      meta: <String, Object?>{
        'division': division,
        'authorizedAreaCount': authorizedAreas.length,
        'authorizedAreas': authorizedAreas.join(','),
        'headquarterCandidateAvailable': authorizedAreas.contains(division),
        'firebaseWrites': 0,
      },
    );

    if (authorizedAreas.contains(division)) {
      final candidate = await fetchArea(division, 'headquarter_fast_path');
      if (candidate != null && candidate.isHeadquarter) {
        final modes = AppModeRegistry.supportedModes(
          candidate.modes,
          allowedIds: accountModeIds,
        );
        final option = LauncherWorkAreaOption(
          division: division,
          areaName: candidate.name.trim(),
          isHeadquarter: true,
          supportedModes: List<AppModeDefinition>.unmodifiable(modes),
          verifiedAreaRecord: candidate,
          dataSource: 'server_hq_fast_path',
        );
        LauncherDiagnostics.record(
          'auth_work_area_direct_fetch_complete',
          meta: <String, Object?>{
            'division': division,
            'requestedAreaCount': 1,
            'successfulAreaCount': 1,
            'availableAreaCount': 1,
            'headquarterCount': 1,
            'headquarterFastPath': true,
            'firebaseAreaDocumentReads': readAttempts,
            'firebaseWrites': 0,
            'dataSource': 'server_hq_fast_path',
          },
        );
        return LauncherWorkAreaResolution(
          hasSnapshot: false,
          division: division,
          areas: <LauncherWorkAreaOption>[option],
          dataSource: 'server_hq_fast_path',
          firebaseAreaDocumentReads: readAttempts,
          serverFallbackUsed: true,
          headquarterFastPath: true,
        );
      }
    }

    final remainingAreas = authorizedAreas
        .where((areaName) => !fetched.containsKey(areaName))
        .toList(growable: false);
    await Future.wait(
      remainingAreas.map(
        (areaName) => fetchArea(areaName, 'authorized_area'),
      ),
    );

    final areas = <LauncherWorkAreaOption>[];
    for (final areaName in authorizedAreas) {
      final record = fetched[areaName];
      if (record == null) continue;
      final modes = AppModeRegistry.supportedModes(
        record.modes,
        allowedIds: accountModeIds,
      );
      if (!record.isHeadquarter && modes.isEmpty) {
        LauncherDiagnostics.record(
          'auth_work_area_direct_fetch_record_filtered',
          meta: <String, Object?>{
            'division': division,
            'area': record.name,
            'reason': 'effective_mode_empty',
            'recordModes': record.modes.join(','),
            'accountModes': accountModeIds.join(','),
          },
        );
        continue;
      }
      areas.add(
        LauncherWorkAreaOption(
          division: division,
          areaName: record.name.trim(),
          isHeadquarter: record.isHeadquarter,
          supportedModes: List<AppModeDefinition>.unmodifiable(modes),
          verifiedAreaRecord: record,
          dataSource: 'server_authorized_areas',
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
      'auth_work_area_direct_fetch_complete',
      meta: <String, Object?>{
        'division': division,
        'requestedAreaCount': readAttempts,
        'successfulAreaCount': fetched.values.whereType<AreaRecord>().length,
        'availableAreaCount': areas.length,
        'headquarterCount': areas.where((area) => area.isHeadquarter).length,
        'headquarterFastPath': false,
        'firebaseAreaDocumentReads': readAttempts,
        'firebaseWrites': 0,
        'dataSource': 'server_authorized_areas',
      },
    );

    return LauncherWorkAreaResolution(
      hasSnapshot: false,
      division: division,
      areas: List<LauncherWorkAreaOption>.unmodifiable(areas),
      dataSource: 'server_authorized_areas',
      firebaseAreaDocumentReads: readAttempts,
      serverFallbackUsed: true,
    );
  }
}
