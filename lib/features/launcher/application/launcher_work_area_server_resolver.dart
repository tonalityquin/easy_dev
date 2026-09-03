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
        'auth_work_area_server_bootstrap_blocked',
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
        dataSource: 'server_bootstrap_unavailable',
        serverFallbackUsed: true,
      );
    }

    if (authorizedAreas.length == 1) {
      final areaName = authorizedAreas.first;
      LauncherDiagnostics.record(
        'auth_work_area_single_server_fetch_start',
        meta: <String, Object?>{
          'division': division,
          'area': areaName,
          'documentId': '$division-$areaName',
          'authorizedAreaCount': 1,
          'firebaseAreaDocumentReadAttempt': 1,
          'firebaseWrites': 0,
        },
      );
      final option = await verifyArea(
        division: division,
        areaName: areaName,
        accountModes: accountModes,
        areaRepository: areaRepository,
        source: 'single_area_snapshot_miss',
      );
      return LauncherWorkAreaResolution(
        hasSnapshot: false,
        division: division,
        areas: option == null
            ? const <LauncherWorkAreaOption>[]
            : <LauncherWorkAreaOption>[option],
        dataSource: option == null
            ? 'server_single_area_missing'
            : 'server_single_area',
        firebaseAreaDocumentReads: 1,
        serverFallbackUsed: true,
        headquarterFastPath: option?.isHeadquarter == true,
      );
    }

    final firstArea = authorizedAreas.first;
    final headquarterCandidate = firstArea == division;
    final option = LauncherWorkAreaOption(
      division: division,
      areaName: firstArea,
      isHeadquarter: headquarterCandidate,
      supportedModes: const <AppModeDefinition>[],
      requiresServerHeadquarterVerification: headquarterCandidate,
      requiresServerAreaResolution: true,
      dataSource: 'user_profile_first_area',
    );
    LauncherDiagnostics.record(
      'auth_work_area_multi_first_bootstrap_ready',
      meta: <String, Object?>{
        'division': division,
        'authorizedAreaCount': authorizedAreas.length,
        'authorizedAreas': authorizedAreas.join(','),
        'selectedArrayIndex': 0,
        'selectedArea': firstArea,
        'headquarterCandidate': headquarterCandidate,
        'firebaseAreaDocumentReads': 0,
        'firebaseWrites': 0,
        'dataSource': 'user_profile_first_area',
      },
    );
    return LauncherWorkAreaResolution(
      hasSnapshot: false,
      division: division,
      areas: <LauncherWorkAreaOption>[option],
      dataSource: 'user_profile_first_area',
      firebaseAreaDocumentReads: 0,
      serverFallbackUsed: true,
      headquarterFastPath: headquarterCandidate,
    );
  }

  static Future<LauncherWorkAreaOption?> verifyArea({
    required String division,
    required String areaName,
    required List<AppModeDefinition> accountModes,
    required AreaRepository areaRepository,
    required String source,
  }) async {
    final normalizedDivision = division.trim();
    final normalizedArea = areaName.trim();
    if (normalizedDivision.isEmpty || normalizedArea.isEmpty) return null;
    LauncherDiagnostics.record(
      'auth_work_area_server_record_start',
      meta: <String, Object?>{
        'division': normalizedDivision,
        'area': normalizedArea,
        'documentId': '$normalizedDivision-$normalizedArea',
        'source': source,
        'firebaseAreaDocumentReadAttempt': 1,
      },
    );
    try {
      final record = await areaRepository.getAreaByName(
        normalizedArea,
        division: normalizedDivision,
        serverOnly: true,
      );
      if (record == null) {
        LauncherDiagnostics.record(
          'auth_work_area_server_record_missing',
          meta: <String, Object?>{
            'division': normalizedDivision,
            'area': normalizedArea,
            'documentId': '$normalizedDivision-$normalizedArea',
            'source': source,
            'firebaseAreaDocumentReads': 1,
          },
        );
        return null;
      }
      final accountModeIds = accountModes.map((mode) => mode.id).toSet();
      final modes = AppModeRegistry.supportedModes(
        record.modes,
        allowedIds: accountModeIds,
      );
      final option = LauncherWorkAreaOption(
        division: normalizedDivision,
        areaName: record.name.trim(),
        isHeadquarter: record.isHeadquarter,
        supportedModes: List<AppModeDefinition>.unmodifiable(modes),
        verifiedAreaRecord: record,
        dataSource: source == 'single_area_snapshot_miss'
            ? 'server_single_area'
            : 'server_first_area_verified',
      );
      LauncherDiagnostics.record(
        'auth_work_area_server_record_success',
        meta: <String, Object?>{
          'division': normalizedDivision,
          'area': record.name.trim(),
          'documentId': '$normalizedDivision-$normalizedArea',
          'source': source,
          'isHeadquarter': record.isHeadquarter,
          'recordModes': record.modes.join(','),
          'effectiveModes': modes.map((mode) => mode.id).join(','),
          'firebaseAreaDocumentReads': 1,
          'firebaseWrites': 0,
        },
      );
      return option;
    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'auth_work_area_server_record_error',
        meta: <String, Object?>{
          'division': normalizedDivision,
          'area': normalizedArea,
          'documentId': '$normalizedDivision-$normalizedArea',
          'source': source,
          'firebaseAreaDocumentReads': 1,
          'firebaseWrites': 0,
          'error': error,
          'stack': stackTrace,
        },
      );
      return null;
    }
  }
}
