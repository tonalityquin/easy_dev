import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/dev/application/area_state.dart';
import '../../features/location/applications/location_state.dart';
import '../../features/payment/applications/bill_state.dart';
import '../../shared/plate/domain/repositories/plate_repository.dart';
import '../init/app_exit_service.dart';
import 'ops_delayed_refresh_gate.dart';

enum OperationalDataSyncResult {
  cancelled,
  completed,
  failed,
}

class OperationalDataSyncWorkflow {
  static const String monthlyParkingKey = 'has_monthly_parking';
  static const String lastSyncAtKey = 'operational_data_last_sync_at';
  static bool _running = false;

  static Future<OperationalDataSyncResult> run({
    required BuildContext context,
    String title = '운영 데이터 동기화',
    String message = '주차 구역, 정산 타입, 월정기 사용 여부를 새로고침하기 전 요청을 준비하고 있습니다.',
  }) async {
    if (_running) return OperationalDataSyncResult.cancelled;

    final areaState = context.read<AreaState>();
    final area = areaState.currentArea.trim();
    final locationState = context.read<LocationState>();
    final billState = context.read<BillState>();
    final plateRepository = context.read<PlateRepository>();
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    if (area.isEmpty) {
      _showFailure(rootContext, '현재 지역 정보가 없어 운영 데이터를 동기화할 수 없습니다.');
      return OperationalDataSyncResult.failed;
    }

    _running = true;
    var dataSaved = false;
    try {
      final shouldRefresh = await OpsDelayedRefreshGate.waitIfNeeded(
        context: context,
        title: title,
        message: message,
      );
      if (!shouldRefresh) {
        return OperationalDataSyncResult.cancelled;
      }
      if (areaState.currentArea.trim() != area) {
        throw StateError('동기화 중 현재 지역이 변경되었습니다.');
      }

      await locationState.clearCurrentAreaCache();
      await billState.clearCurrentAreaCache();
      await _clearOperationalMetadata();

      await locationState.manualLocationRefreshStrict();
      await billState.manualBillRefreshStrict();
      if (areaState.currentArea.trim() != area) {
        throw StateError('동기화 중 현재 지역이 변경되었습니다.');
      }

      final hasMonthlyParking = await plateRepository.hasMonthlyParkingByArea(
        area: area,
      );
      await _saveOperationalMetadata(
        hasMonthlyParking: hasMonthlyParking,
        syncedAtIso: DateTime.now().toIso8601String(),
      );
      dataSaved = true;

      if (!rootContext.mounted) {
        throw StateError('완료 안내 화면을 표시할 수 없습니다.');
      }

      await showDialog<void>(
        context: rootContext,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('운영 데이터 동기화 완료'),
            content: const Text(
              '기존 로컬 운영 데이터를 삭제하고 최신 데이터를 새로 저장했습니다.\n\n변경 사항 적용을 위해 앱을 종료합니다. 앱을 다시 실행해 주세요.',
            ),
            actions: [
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.power_settings_new_rounded),
                label: const Text('확인 및 종료'),
              ),
            ],
          );
        },
      );

      if (rootContext.mounted) {
        await AppExitService.exitApp(rootContext);
      }
      return OperationalDataSyncResult.completed;
    } catch (_) {
      if (!dataSaved) {
        try {
          await locationState.clearCurrentAreaCache();
        } catch (_) {}
        try {
          await billState.clearCurrentAreaCache();
        } catch (_) {}
        try {
          await _clearOperationalMetadata();
        } catch (_) {}
      }
      if (rootContext.mounted) {
        _showFailure(rootContext, '운영 데이터 동기화에 실패했습니다.');
      }
      return OperationalDataSyncResult.failed;
    } finally {
      _running = false;
    }
  }

  static Future<void> _clearOperationalMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(monthlyParkingKey);
    await prefs.remove(lastSyncAtKey);
    await prefs.reload();
    if (prefs.containsKey(monthlyParkingKey) ||
        prefs.containsKey(lastSyncAtKey)) {
      throw StateError('기존 운영 데이터 메타 정보 삭제 검증 실패');
    }
  }

  static Future<void> _saveOperationalMetadata({
    required bool hasMonthlyParking,
    required String syncedAtIso,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final monthlySaved = await prefs.setBool(
      monthlyParkingKey,
      hasMonthlyParking,
    );
    final syncAtSaved = await prefs.setString(lastSyncAtKey, syncedAtIso);
    if (!monthlySaved || !syncAtSaved) {
      throw StateError('운영 데이터 메타 정보 저장 실패');
    }
    await prefs.reload();
    if (prefs.getBool(monthlyParkingKey) != hasMonthlyParking ||
        prefs.getString(lastSyncAtKey) != syncedAtIso) {
      throw StateError('운영 데이터 메타 정보 저장 검증 실패');
    }
  }

  static void _showFailure(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }
}
