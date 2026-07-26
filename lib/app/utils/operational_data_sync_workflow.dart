import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../models/capability.dart';
import '../../features/dev/application/area_state.dart';
import '../../features/location/applications/location_state.dart';
import '../../features/payment/applications/bill_state.dart';
import '../../features/sector/applications/sector_state.dart';
import '../../shared/plate/domain/repositories/plate_repository.dart';
import '../init/app_exit_service.dart';
import 'developer_operation_status_dialog.dart';
import 'ops_delayed_refresh_gate.dart';
import 'snackbar_helper.dart';

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
    String message =
        '주차 구역, 섹터, 정산 타입, 월정기 사용 여부를 새로고침하기 전 요청을 준비하고 있습니다.',
    bool usePromptUi = false,
  }) async {
    if (_running) {
      debugPrint('[$title] 이미 운영 데이터 동기화가 진행 중입니다.');
      return OperationalDataSyncResult.cancelled;
    }

    _running = true;
    try {
      final areaState = context.read<AreaState>();
      final area = areaState.currentArea.trim();
      final locationState = context.read<LocationState>();
      final billState = context.read<BillState>();
      final sectorState = context.read<SectorState>();
      final hasSectorCapability =
          areaState.capabilitiesOfCurrentArea.contains(Capability.sector);
      final plateRepository = context.read<PlateRepository>();
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      final trace = await DeveloperOperationTrace.start(
        context: rootContext,
        title: title,
        initialMessage: '운영 데이터 동기화 요청을 확인하고 있습니다.',
        usePromptUi: usePromptUi,
      );

      if (area.isEmpty) {
        const failureMessage = '현재 지역 정보가 없어 운영 데이터를 동기화할 수 없습니다.';
        await trace.fail(failureMessage);
        if (!trace.developerMode && rootContext.mounted) {
          _showFailure(
            rootContext,
            failureMessage,
            usePromptUi: usePromptUi,
          );
        }
        return OperationalDataSyncResult.failed;
      }

      var dataSaved = false;
      try {
        trace.log('현재 지역을 확인했습니다: $area', progress: 0.06);
        trace.log('실행 전 동기화 게이트를 확인하고 있습니다.', progress: 0.12);

        final shouldRefresh = await OpsDelayedRefreshGate.waitIfNeeded(
          context: context,
          title: title,
          message: message,
          usePromptUi: usePromptUi,
        );
        if (!shouldRefresh) {
          trace.log('사용자가 운영 데이터 동기화를 취소했습니다.');
          return OperationalDataSyncResult.cancelled;
        }

        if (areaState.currentArea.trim() != area) {
          throw StateError('동기화 중 현재 지역이 변경되었습니다.');
        }

        trace.log('기존 주차 구역 캐시를 삭제하고 있습니다.', progress: 0.18);
        await locationState.clearCurrentAreaCache();

        trace.log('기존 정산 데이터 캐시를 삭제하고 있습니다.', progress: 0.26);
        await billState.clearCurrentAreaCache();

        trace.log('기존 섹터 데이터 캐시를 삭제하고 있습니다.', progress: 0.34);
        await sectorState.clearCurrentAreaCache();

        trace.log('기존 운영 메타 정보를 삭제하고 있습니다.', progress: 0.42);
        await _clearOperationalMetadata();

        trace.log('최신 주차 구역 데이터를 내려받고 있습니다.', progress: 0.54);
        await locationState.manualLocationRefreshStrict();

        trace.log('최신 정산 타입 데이터를 내려받고 있습니다.', progress: 0.66);
        await billState.manualBillRefreshStrict();

        if (hasSectorCapability) {
          trace.log(
            '최신 섹터 데이터를 내려받아 로컬에 저장하고 있습니다.',
            progress: 0.72,
          );
          trace.log(
            '섹터 캐시의 항목 형식과 지역 범위를 검증할 준비를 하고 있습니다.',
            progress: 0.75,
          );
          final sectorCount = await sectorState.manualSectorRefreshStrict();
          trace.log(
            '섹터 로컬 캐시 무결성 검증 완료: '
            'area=$area, count=$sectorCount, '
            'cacheKey=${SectorState.cacheKeyForArea(area)}, '
            'checks=type,fields,area,duplicateId,duplicateName,date,state',
            progress: 0.79,
          );
        } else {
          trace.log(
            '현재 지역에 sector 기능이 없어 섹터 로컬 다운로드를 건너뜁니다.',
            progress: 0.78,
          );
        }

        if (areaState.currentArea.trim() != area) {
          throw StateError('동기화 중 현재 지역이 변경되었습니다.');
        }

        trace.log('월정기 사용 여부를 확인하고 있습니다.', progress: 0.84);
        final hasMonthlyParking = await plateRepository.hasMonthlyParkingByArea(
          area: area,
        );
        trace.log(
          '월정기 사용 여부 확인 완료: ${hasMonthlyParking ? '사용' : '미사용'}',
          progress: 0.88,
        );

        final syncedAtIso = DateTime.now().toIso8601String();
        trace.log('새 운영 메타 정보를 저장하고 검증하고 있습니다.', progress: 0.94);
        await _saveOperationalMetadata(
          hasMonthlyParking: hasMonthlyParking,
          syncedAtIso: syncedAtIso,
        );
        trace.log('운영 메타 정보 저장 완료: $syncedAtIso', progress: 0.98);
        dataSaved = true;

        if (trace.developerMode) {
          await trace.succeed(
            '운영 데이터와 섹터 로컬 다운로드가 완료되었습니다. 개발자 모드에서는 앱을 종료하지 않습니다.',
          );
          return OperationalDataSyncResult.completed;
        }

        await trace.succeed('운영 데이터와 섹터 로컬 다운로드가 완료되었습니다.');

        if (!rootContext.mounted) {
          throw StateError('완료 안내 화면을 표시할 수 없습니다.');
        }

        Widget completionDialog(BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('운영 데이터 동기화 완료'),
            content: const Text(
              '기존 로컬 운영 데이터를 삭제하고 주차 구역, 섹터, 정산 데이터를 최신 상태로 저장했습니다.\n\n변경 사항 적용을 위해 앱을 종료합니다. 앱을 다시 실행해 주세요.',
            ),
            actions: <Widget>[
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.power_settings_new_rounded),
                label: const Text('확인 및 종료'),
              ),
            ],
          );
        }

        if (usePromptUi) {
          await showPromptOverlayDialog<void>(
            context: rootContext,
            barrierDismissible: false,
            builder: completionDialog,
          );
        } else {
          await showDialog<void>(
            context: rootContext,
            barrierDismissible: false,
            builder: completionDialog,
          );
        }

        if (rootContext.mounted) {
          await AppExitService.exitApp(
            rootContext,
            usePromptUi: usePromptUi,
          );
        }
        return OperationalDataSyncResult.completed;
      } catch (error, stackTrace) {
        if (!dataSaved) {
          trace.log('실패 후 주차 구역 캐시를 정리하고 있습니다.');
          try {
            await locationState.clearCurrentAreaCache();
          } catch (cleanupError) {
            trace.log('주차 구역 캐시 정리 실패: $cleanupError');
          }

          trace.log('실패 후 정산 데이터 캐시를 정리하고 있습니다.');
          try {
            await billState.clearCurrentAreaCache();
          } catch (cleanupError) {
            trace.log('정산 데이터 캐시 정리 실패: $cleanupError');
          }

          trace.log('실패 후 섹터 데이터 캐시를 정리하고 있습니다.');
          try {
            await sectorState.clearCurrentAreaCache();
          } catch (cleanupError) {
            trace.log('섹터 데이터 캐시 정리 실패: $cleanupError');
          }

          trace.log('실패 후 운영 메타 정보를 정리하고 있습니다.');
          try {
            await _clearOperationalMetadata();
          } catch (cleanupError) {
            trace.log('운영 메타 정보 정리 실패: $cleanupError');
          }
        }

        const failureMessage = '운영 데이터 동기화에 실패했습니다.';
        await trace.fail(
          failureMessage,
          error: error,
          stackTrace: stackTrace,
        );

        if (!trace.developerMode && rootContext.mounted) {
          _showFailure(
            rootContext,
            failureMessage,
            usePromptUi: usePromptUi,
          );
        }
        return OperationalDataSyncResult.failed;
      }
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

  static void _showFailure(
    BuildContext context,
    String message, {
    required bool usePromptUi,
  }) {
    if (usePromptUi) {
      showFailedSnackbar(context, message, usePromptUi: true);
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }
}
