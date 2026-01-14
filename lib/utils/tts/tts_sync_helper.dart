import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../states/area/area_state.dart';
import '../snackbar_helper.dart';
import 'plate_tts_listener_service.dart';
import 'tts_user_filters.dart';

/// TTS 설정(필터)을 저장/동기화하는 공용 헬퍼입니다.
///
/// DashboardSetting의 "실시간 적용" 흐름을 기준으로 다음을 일관되게 수행합니다.
/// 1) (옵션) SharedPreferences 저장
/// 2) 앱 isolate: PlateTTS 마스터 on/off + 필터 즉시 반영
/// 3) FG isolate: { area, ttsFilters } 전송
/// 4) (옵션) snackbar_helper로 성공/실패 피드백
class TtsSyncHelper {
  /// DashboardSetting 기준 apply: 저장 + 앱/FG 동기화 + 스낵바(옵션)
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

      // ✅ PlateTTS 마스터 on/off는 parking/departure/completed 합성으로 결정
      final masterOn = filters.parking || filters.departure || filters.completed;
      await PlateTtsListenerService.setEnabled(masterOn);

      // ✅ 앱 isolate 필터 즉시 반영
      PlateTtsListenerService.updateFilters(filters);

      // ✅ FG isolate에도 최신 필터 전달 (area가 비어있을 수도 있음)
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

  /// 최신 prefs를 로드한 뒤 저장 없이 동기화만 수행합니다.
  ///
  /// - BottomSheet 종료 후 보수적 재동기화 등에서 사용
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
