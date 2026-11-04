import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/ops_delayed_refresh_gate.dart';
import '../../../app/utils/status_dialog.dart';
import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../../location/applications/location_state.dart';
import '../../payment/applications/bill_state.dart';
import '../../sector/applications/sector_state.dart';
import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import 'sensor_debug_trace.dart';

enum SensorOperationalDataSyncResult {
  cancelled,
  completed,
  failed,
}

class SensorOperationalDataSyncWorkflow {
  SensorOperationalDataSyncWorkflow._();

  static bool _running = false;

  static Future<SensorOperationalDataSyncResult> runCurrentArea({
    required BuildContext context,
  }) async {
    if (_running) {
      SensorDebugTrace.record(
        'SensorDataSync',
        'request_skipped',
        <String, Object?>{'reason': 'already_running'},
      );
      return SensorOperationalDataSyncResult.cancelled;
    }

    _running = true;
    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();
      final session = userState.session;
      final sessionId = session?.id.trim() ?? '';
      final area = areaState.currentArea.trim();
      final locationState = context.read<LocationState>();
      final billState = context.read<BillState>();
      final sectorState = context.read<SectorState>();
      final localRepository = context.read<OperationalLocalRepository>();
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      final trace = await DeveloperOperationTrace.start(
        context: rootContext,
        title: '센서 데이터 내려받기',
        initialMessage: '현재 지역의 센서 운영 데이터를 확인합니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 내려받기 상태와 debugPrint 코드를 확인할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: locations, bill, sector 데이터를 내려받습니다.',
      );

      SensorDebugTrace.record(
        'SensorDataSync',
        'started',
        <String, Object?>{
          'area': area,
          'sessionIdPresent': sessionId.isNotEmpty,
          'developerMode': trace.developerMode,
        },
      );

      if (session == null) {
        const message = '로그인 세션 정보가 없어 데이터를 내려받을 수 없습니다.';
        await trace.fail(message);
        if (!trace.developerMode && rootContext.mounted) {
          await StatusDialog.showFailure(
            rootContext,
            title: '센서 데이터 내려받기 실패',
            description: message,
            useCommonUi: true,
          );
        }
        return SensorOperationalDataSyncResult.failed;
      }

      if (area.isEmpty) {
        const message = '현재 지역 정보가 없어 데이터를 내려받을 수 없습니다.';
        await trace.fail(message);
        if (!trace.developerMode && rootContext.mounted) {
          await StatusDialog.showFailure(
            rootContext,
            title: '센서 데이터 내려받기 실패',
            description: message,
            useCommonUi: true,
          );
        }
        return SensorOperationalDataSyncResult.failed;
      }

      try {
        trace.log(
          '로그인 세션과 현재 지역을 확인했습니다: area=$area sessionIdPresent=${sessionId.isNotEmpty}',
          progress: 0.05,
        );

        final shouldDownload = await OpsDelayedRefreshGate.waitIfNeeded(
          context: context,
          title: '센서 데이터 내려받기',
          message: '현재 지역의 locations, bill, sector 데이터를 내려받을 준비를 하고 있습니다.',
          useCommonUi: true,
        );
        if (!shouldDownload) {
          trace.log('사용자가 센서 데이터 내려받기를 취소했습니다.', progress: 1);
          SensorDebugTrace.record(
            'SensorDataSync',
            'cancelled',
            <String, Object?>{'area': area},
          );
          return SensorOperationalDataSyncResult.cancelled;
        }

        final latestSession = userState.session;
        if (latestSession == null || latestSession.id.trim() != sessionId) {
          throw StateError('내려받기 중 로그인 세션이 변경되었습니다.');
        }
        if (areaState.currentArea.trim() != area) {
          throw StateError('내려받기 중 현재 지역이 변경되었습니다.');
        }

        trace.log('기존 locations SQLite 데이터를 삭제합니다: area=$area', progress: 0.12);
        await locationState.clearAreaCache(area);
        trace.log(
          'locations 삭제 검증 완료: area=$area remaining=${await localRepository.countLocations(area)}',
          progress: 0.20,
        );

        trace.log('기존 bill SQLite 데이터를 삭제합니다: area=$area', progress: 0.24);
        await billState.clearAreaCache(area);
        trace.log(
          'bill 삭제 검증 완료: area=$area general=${await localRepository.countGeneralBills(area)} regular=${await localRepository.countRegularBills(area)}',
          progress: 0.32,
        );

        trace.log('기존 sector SQLite 데이터를 삭제합니다: area=$area', progress: 0.36);
        await sectorState.clearAreaCache(area);
        trace.log(
          'sector 삭제 검증 완료: area=$area remaining=${await localRepository.countSectors(area)}',
          progress: 0.44,
        );

        if (areaState.currentArea.trim() != area) {
          throw StateError('SQLite 정리 중 현재 지역이 변경되었습니다.');
        }

        trace.log('Firestore locations 데이터를 내려받습니다: area=$area', progress: 0.50);
        await locationState.manualLocationRefreshStrictForArea(area);
        final locationCount = await localRepository.countLocations(area);
        trace.log(
          'locations 저장 완료: area=$area count=$locationCount',
          progress: 0.66,
        );

        trace.log('Firestore bill 데이터를 내려받습니다: area=$area', progress: 0.70);
        await billState.manualBillRefreshStrictForArea(area);
        final generalBillCount = await localRepository.countGeneralBills(area);
        final regularBillCount = await localRepository.countRegularBills(area);
        trace.log(
          'bill 저장 완료: area=$area general=$generalBillCount regular=$regularBillCount',
          progress: 0.82,
        );

        trace.log('Firestore sector 데이터를 내려받습니다: area=$area', progress: 0.86);
        final sectorCount =
            await sectorState.manualSectorRefreshStrictForArea(area);
        trace.log(
          'sector 저장 완료: area=$area count=$sectorCount',
          progress: 0.96,
        );

        if (areaState.currentArea.trim() != area) {
          throw StateError('데이터 저장 중 현재 지역이 변경되었습니다.');
        }

        final summary =
            'area=$area locations=$locationCount generalBills=$generalBillCount regularBills=$regularBillCount sectors=$sectorCount';
        SensorDebugTrace.record(
          'SensorDataSync',
          'completed',
          <String, Object?>{
            'area': area,
            'locations': locationCount,
            'generalBills': generalBillCount,
            'regularBills': regularBillCount,
            'sectors': sectorCount,
          },
        );
        await trace.succeed('센서 데이터 내려받기가 완료되었습니다: $summary');

        if (!trace.developerMode && rootContext.mounted) {
          await StatusDialog.showSuccess(
            rootContext,
            title: '센서 데이터 내려받기 완료',
            description:
                'locations $locationCount · bill ${generalBillCount + regularBillCount} · sector $sectorCount',
            useCommonUi: true,
          );
        }
        return SensorOperationalDataSyncResult.completed;
      } catch (error, stackTrace) {
        trace.log('실패 후 locations SQLite 데이터를 정리합니다.');
        try {
          await locationState.clearAreaCache(area);
        } catch (cleanupError) {
          trace.log('locations 정리 실패: $cleanupError');
        }

        trace.log('실패 후 bill SQLite 데이터를 정리합니다.');
        try {
          await billState.clearAreaCache(area);
        } catch (cleanupError) {
          trace.log('bill 정리 실패: $cleanupError');
        }

        trace.log('실패 후 sector SQLite 데이터를 정리합니다.');
        try {
          await sectorState.clearAreaCache(area);
        } catch (cleanupError) {
          trace.log('sector 정리 실패: $cleanupError');
        }

        SensorDebugTrace.record(
          'SensorDataSync',
          'failed',
          <String, Object?>{
            'area': area,
            'error': error,
            'stackTrace': stackTrace,
          },
        );
        await trace.fail(
          '센서 데이터 내려받기에 실패했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
        if (!trace.developerMode && rootContext.mounted) {
          await StatusDialog.showFailure(
            rootContext,
            title: '센서 데이터 내려받기 실패',
            description: error.toString(),
            useCommonUi: true,
          );
        }
        return SensorOperationalDataSyncResult.failed;
      }
    } finally {
      _running = false;
    }
  }
}
