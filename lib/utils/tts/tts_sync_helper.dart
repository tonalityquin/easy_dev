import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../features/dev/application/area_state.dart';
import '../snackbar_helper.dart';
import 'plate_tts_listener_service.dart';
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

      final masterOn =
          filters.parking || filters.departure || filters.completed;
      await PlateTtsListenerService.setEnabled(masterOn);

      PlateTtsListenerService.updateFilters(filters);

      final area = context.read<AreaState>().currentArea;
      FlutterForegroundTask.sendDataToTask({
        'area': area,
        'ttsFilters': filters.toMap(),
      });

      if (showSnackbar) {
        showSuccessSnackbar(context, successMessage);
      }
    } catch (e) {
      if (showSnackbar) {
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
