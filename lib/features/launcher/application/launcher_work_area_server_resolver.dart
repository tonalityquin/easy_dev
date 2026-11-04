import '../../account/domain/models/user/user_model.dart';
import '../../../app/models/account_area_access.dart';
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
    if (division.isEmpty) {
      return const LauncherWorkAreaResolution(
        hasSnapshot: false,
        division: '',
        areas: <LauncherWorkAreaOption>[],
        dataSource: 'division_missing',
        serverFallbackUsed: true,
      );
    }

    try {
      final records = await areaRepository.getAreasByDivision(
        division,
        serverOnly: true,
      );
      final ids = accountModes.map((mode) => mode.id).toSet();
      final areas = <LauncherWorkAreaOption>[];
      for (final record in records) {
        if (record.division.trim() != division || record.name.trim().isEmpty) {
          continue;
        }
        final modes = AppModeRegistry.supportedModes(
          record.modes,
          allowedIds: ids,
        );
        final assigned = AccountAreaAccess.isAssigned(
          user.areas,
          record.name,
        );
        final allowed = AccountAreaAccess.canUseArea(
          role: user.role,
          division: division,
          divisions: user.divisions,
          areas: user.areas,
          area: record.name,
          isHeadquarter: record.isHeadquarter,
        ) && (record.isHeadquarter || modes.isNotEmpty);
        areas.add(LauncherWorkAreaOption(
          division: division,
          areaName: record.name.trim(),
          isHeadquarter: record.isHeadquarter,
          supportedModes: List<AppModeDefinition>.unmodifiable(modes),
          isAllowed: allowed,
          deniedReason: AccountAreaAccess.deniedReason(
            isAssigned: assigned,
            isHeadquarter: record.isHeadquarter,
            isHeadOffice: AccountAreaAccess.isHeadOfficeRole(user.role),
            modeAvailable: modes.isNotEmpty,
          ),
          verifiedAreaRecord: record,
          dataSource: 'server_division_areas',
        ));
      }
      areas.sort((a, b) {
        if (a.isHeadquarter != b.isHeadquarter) {
          return a.isHeadquarter ? -1 : 1;
        }
        return a.areaName.toLowerCase().compareTo(b.areaName.toLowerCase());
      });
      LauncherDiagnostics.record(
        'auth_work_area_server_division_ready',
        meta: <String, Object?>{
          'division': division,
          'areaCount': areas.length,
          'allowedAreaCount': areas.where((area) => area.isAllowed).length,
          'firebaseAreaDocumentReads': records.length,
          'firebaseWrites': 0,
          'dataSource': 'server_division_areas',
        },
      );
      return LauncherWorkAreaResolution(
        hasSnapshot: false,
        division: division,
        areas: List<LauncherWorkAreaOption>.unmodifiable(areas),
        dataSource: 'server_division_areas',
        firebaseAreaDocumentReads: records.length,
        serverFallbackUsed: true,
        headquarterFastPath: false,
      );
    } catch (error) {
      LauncherDiagnostics.record(
        'auth_work_area_server_division_error',
        meta: <String, Object?>{
          'division': division,
          'errorType': error.runtimeType.toString(),
        },
      );
      return LauncherWorkAreaResolution(
        hasSnapshot: false,
        division: division,
        areas: const <LauncherWorkAreaOption>[],
        dataSource: 'server_division_error',
        serverFallbackUsed: true,
      );
    }
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
