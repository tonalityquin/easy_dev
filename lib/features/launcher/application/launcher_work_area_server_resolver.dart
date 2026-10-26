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
    final homeCompany = user.companyId.trim();
    final divisions = user.divisions
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));
    final allowedNames = user.areas.map((value) => value.trim()).toSet();
    final ids = user.areaIds.map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final options = <LauncherWorkAreaOption>[];
    if (ids.isNotEmpty) {
      for (final id in ids) {
        for (final division in divisions) {
          final prefix = '$division-';
          if (!id.startsWith(prefix)) continue;
          final name = id.substring(prefix.length).trim();
          if (!allowedNames.contains(name)) break;
          final isHeadquarter = name == division;
          options.add(LauncherWorkAreaOption(
            division: division,
            areaName: name,
            isHeadquarter: isHeadquarter,
            supportedModes: const <AppModeDefinition>[],
            requiresServerHeadquarterVerification: isHeadquarter,
            requiresServerAreaResolution: true,
            dataSource: 'account_area_ids',
          ));
          break;
        }
      }
    } else if (homeCompany.isNotEmpty && divisions.contains(homeCompany)) {
      for (final name in allowedNames) {
        final isHeadquarter = name == homeCompany;
        options.add(LauncherWorkAreaOption(
          division: homeCompany,
          areaName: name,
          isHeadquarter: isHeadquarter,
          supportedModes: const <AppModeDefinition>[],
          requiresServerHeadquarterVerification: isHeadquarter,
          requiresServerAreaResolution: true,
          dataSource: 'legacy_area_names_pending_verification',
        ));
      }
    }
    options.sort((a, b) {
      final homeA = a.division == homeCompany;
      final homeB = b.division == homeCompany;
      if (homeA != homeB) return homeA ? -1 : 1;
      if (a.isHeadquarter != b.isHeadquarter) {
        return a.isHeadquarter ? -1 : 1;
      }
      return '${a.division}/${a.areaName}'
          .compareTo('${b.division}/${b.areaName}');
    });
    LauncherDiagnostics.record(
      'auth_work_area_server_bootstrap_ready',
      meta: <String, Object?>{
        'division': homeCompany,
        'authorizedAreaCount': options.length,
        'dataSource': 'account_area_ids',
        'firebaseAreaDocumentReads': 0,
        'firebaseWrites': 0,
      },
    );
    return LauncherWorkAreaResolution(
      hasSnapshot: false,
      division: homeCompany,
      areas: List<LauncherWorkAreaOption>.unmodifiable(options),
      dataSource: 'account_area_ids',
      serverFallbackUsed: true,
      headquarterFastPath: options.isNotEmpty && options.first.isHeadquarter,
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
