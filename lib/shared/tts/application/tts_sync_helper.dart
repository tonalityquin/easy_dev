import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/snackbar_helper.dart';
import '../../../features/account/applications/user_state.dart';
import '../../../features/dev/application/area_state.dart';
import '../../work_session/application/work_area_session_coordinator.dart';
import 'plate_tts_session_diagnostics.dart';
import 'tts_user_filters.dart';

class TtsSyncHelper {
  static Future<void> apply(
    BuildContext context,
    TtsUserFilters filters, {
    bool save = true,
    bool showSnackbar = true,
    String successMessage = 'TTS 설정이 적용되었습니다.',
  }) async {
    try {
      if (save) {
        await filters.save();
      }

      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();
      final area = areaState.currentArea.trim();
      final homeArea = userState.area.trim();
      final currentRecord = areaState.currentRecord;
      final result = await WorkAreaSessionCoordinator.activate(
        currentArea: area,
        division: areaState.currentDivision.trim().isNotEmpty
            ? areaState.currentDivision.trim()
            : userState.division.trim(),
        homeArea: homeArea,
        currentIsHeadquarter: currentRecord?.isHeadquarter,
        homeIsHeadquarter:
            homeArea.isNotEmpty && homeArea == area
                ? currentRecord?.isHeadquarter
                : null,
        filters: filters,
        source: save ? 'tts_settings_save' : 'tts_settings_sync',
      );
      PlateTtsSessionDiagnostics.record(
        'settings_sync_complete',
        meta: <String, Object?>{
          'area': area,
          'mode': result.mode,
          'foregroundServiceRunning': result.foregroundServiceRunning,
          'foregroundOwner': result.foregroundOwner,
          'appFallbackListening': result.appFallbackListening,
        },
      );

      if (showSnackbar && context.mounted) {
        showSuccessSnackbar(context, successMessage);
      }
    } catch (e) {
      PlateTtsSessionDiagnostics.record(
        'settings_sync_failed',
        meta: <String, Object?>{'error': e},
      );
      if (showSnackbar && context.mounted) {
        showFailedSnackbar(context, '적용 실패: $e');
      }
      rethrow;
    }
  }

  static Future<TtsUserFilters> loadAndSync(
    BuildContext context, {
    bool showSnackbar = false,
  }) async {
    final filters = await TtsUserFilters.load();
    await apply(
      context,
      filters,
      save: false,
      showSnackbar: showSnackbar,
    );
    return filters;
  }
}
