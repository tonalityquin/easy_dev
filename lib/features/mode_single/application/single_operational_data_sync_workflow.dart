import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/init/app_exit_service.dart';
import '../../../app/models/capability.dart';
import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/ops_delayed_refresh_gate.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../shared/area_remote_settings/application/local_area_capability_refresh.dart';
import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../../location/applications/location_state.dart';
import '../../payment/applications/bill_state.dart';
import '../../sector/applications/sector_state.dart';
import '../../rule/applications/rule_state.dart';

enum SingleOperationalDataSyncResult {
  cancelled,
  completed,
  failed,
}

class SingleOperationalDataSyncWorkflow {
  static bool _running = false;

  static Future<SingleOperationalDataSyncResult> runCurrentArea({
    required BuildContext context,
    bool useCommonUi = true,
  }) {
    return run(
      context: context,
      title: '운영 데이터 동기화',
      message: '현재 지역의 주차 구역, 섹터, 정산, 업무 규칙 데이터를 로컬에 내려받기 전 요청을 준비하고 있습니다.',
      useCommonUi: useCommonUi,
    );
  }

  static Future<SingleOperationalDataSyncResult> run({
    required BuildContext context,
    String title = '운영 데이터 동기화',
    String message =
        '현재 지역의 주차 구역, 섹터, 정산, 업무 규칙 데이터를 로컬에 내려받기 전 요청을 준비하고 있습니다.',
    bool useCommonUi = false,
  }) async {
    if (_running) {
      debugPrint('[$title][Single] 이미 운영 데이터 동기화가 진행 중입니다.');
      return SingleOperationalDataSyncResult.cancelled;
    }

    _running = true;
    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();
      final session = userState.session;
      final area = session?.selectedArea.trim() ?? '';
      final division = session != null && session.divisions.isNotEmpty
          ? session.divisions.first.trim()
          : '';
      final locationState = context.read<LocationState>();
      final billState = context.read<BillState>();
      final sectorState = context.read<SectorState>();
      final ruleState = context.read<RuleState>();
      final localRepository = context.read<OperationalLocalRepository>();
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      final trace = await DeveloperOperationTrace.start(
        context: rootContext,
        title: title,
        initialMessage: '운영 데이터 동기화 요청을 확인하고 있습니다.',
        useCommonUi: useCommonUi,
        developerModeMessage:
            '개발자 모드 ON: SQLite 동기화 debugPrint 코드를 클립보드로 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF: 완료 후 앱을 종료합니다.',
      );

      trace.log(
        'singleSyncImplementation=independent locationSource=firestore_explicit billSource=firestore_explicit sectorSource=firestore_explicit ruleSource=firestore_explicit viewCollection=false monthlyPresenceLookup=false tts=false',
        progress: 0.02,
      );

      if (session == null) {
        const failureMessage = '로그인 세션 정보가 없어 운영 데이터를 동기화할 수 없습니다.';
        await trace.fail(failureMessage);
        if (!trace.developerMode && rootContext.mounted) {
          _showFailure(
            rootContext,
            failureMessage,
            useCommonUi: useCommonUi,
          );
        }
        return SingleOperationalDataSyncResult.failed;
      }

      if (area.isEmpty) {
        const failureMessage = '선택 지역 정보가 없어 운영 데이터를 동기화할 수 없습니다.';
        await trace.fail(failureMessage);
        if (!trace.developerMode && rootContext.mounted) {
          _showFailure(
            rootContext,
            failureMessage,
            useCommonUi: useCommonUi,
          );
        }
        return SingleOperationalDataSyncResult.failed;
      }

      if (division.isEmpty) {
        const failureMessage = '선택 지역의 회사 정보가 없어 운영 데이터를 동기화할 수 없습니다.';
        await trace.fail(failureMessage);
        if (!trace.developerMode && rootContext.mounted) {
          _showFailure(
            rootContext,
            failureMessage,
            useCommonUi: useCommonUi,
          );
        }
        return SingleOperationalDataSyncResult.failed;
      }

      if (areaState.currentArea.trim() != area ||
          areaState.currentDivision.trim() != division) {
        const failureMessage = '현재 AreaState와 로그인 선택 지역이 일치하지 않습니다.';
        await trace.fail(failureMessage);
        if (!trace.developerMode && rootContext.mounted) {
          _showFailure(
            rootContext,
            failureMessage,
            useCommonUi: useCommonUi,
          );
        }
        return SingleOperationalDataSyncResult.failed;
      }

      var dataSaved = false;
      try {
        trace.log('현재 지역 설정을 확인했습니다.', progress: 0.06);
        trace.log('실행 전 동기화 게이트를 확인하고 있습니다.', progress: 0.12);

        final shouldRefresh = await OpsDelayedRefreshGate.waitIfNeeded(
          context: context,
          title: title,
          message: message,
          useCommonUi: useCommonUi,
        );
        if (!shouldRefresh) {
          trace.log('사용자가 운영 데이터 동기화를 취소했습니다.');
          return SingleOperationalDataSyncResult.cancelled;
        }

        final latestSessionBeforeAreaRefresh = userState.session;
        final latestSelectedArea =
            latestSessionBeforeAreaRefresh?.selectedArea.trim() ?? '';
        final latestDivision = latestSessionBeforeAreaRefresh != null &&
                latestSessionBeforeAreaRefresh.divisions.isNotEmpty
            ? latestSessionBeforeAreaRefresh.divisions.first.trim()
            : '';
        if (latestSelectedArea != area || latestDivision != division) {
          throw StateError('동기화 중 로그인 선택 지역이 변경되었습니다.');
        }
        if (areaState.currentArea.trim() != area ||
            areaState.currentDivision.trim() != division) {
          throw StateError('동기화 중 현재 AreaState 지역이 변경되었습니다.');
        }

        final refreshedArea = await areaState.refreshCurrentAreaSnapshotFromServer(
          division: division,
          area: area,
          onLog: trace.log,
          source: 'single_operational_data_sync',
          progressStart: 0.13,
          progressEnd: 0.155,
        );
        trace.log(
          '현재 선택 지역 Area Snapshot 최신화 완료: division=$division area=$area emailPresent=${refreshedArea.email.trim().isNotEmpty} capabilities=${LocalAreaCapabilityRefresh.keys(refreshedArea.capabilities)} modes=${refreshedArea.modes.join(',')} areaRemoteRead=1 sqliteAreaWrite=1 sqliteVerified=true areaStateApplied=true',
          progress: 0.157,
        );

        final latestSessionAfterAreaRefresh = userState.session;
        final selectedAreaAfterRefresh =
            latestSessionAfterAreaRefresh?.selectedArea.trim() ?? '';
        final divisionAfterRefresh = latestSessionAfterAreaRefresh != null &&
                latestSessionAfterAreaRefresh.divisions.isNotEmpty
            ? latestSessionAfterAreaRefresh.divisions.first.trim()
            : '';
        if (selectedAreaAfterRefresh != area || divisionAfterRefresh != division) {
          throw StateError('Area Snapshot 최신화 중 로그인 선택 지역이 변경되었습니다.');
        }

        final capabilityRefresh = await LocalAreaCapabilityRefresh.refresh(
          areaState: areaState,
          division: division,
          area: area,
          source: 'single_operational_data_sync',
          onLog: trace.log,
          progressStart: 0.158,
          progressEnd: 0.172,
          requireSnapshot: true,
        );

        final capabilities = areaState.capabilitiesOfCurrentArea;
        final hasBillCapability = capabilities.contains(Capability.bill);
        final hasSectorCapability = capabilities.contains(Capability.sector);
        final hasRuleCapability = capabilities.contains(Capability.rule);
        trace.log(
          '지역 capability 적용 상태를 확인했습니다: snapshotFound=${capabilityRefresh.snapshotFound} applied=${capabilityRefresh.applied} changed=${capabilityRefresh.changed} capabilities=${LocalAreaCapabilityRefresh.keys(capabilities)} remoteRead=0 remoteWrite=0',
          progress: 0.175,
        );

        trace.log(
          'SQLite에서 현재 지역 주차 구역을 삭제하고 있습니다: area=$area',
          progress: 0.18,
        );
        await locationState.clearAreaCache(area);
        trace.log(
          '주차 구역 삭제 검증 완료: area=$area remaining=${await localRepository.countLocations(area)}',
          progress: 0.20,
        );

        trace.log(
          '지역 capability를 확인했습니다: bill=$hasBillCapability sector=$hasSectorCapability rule=$hasRuleCapability',
          progress: 0.22,
        );

        trace.log(
          'SQLite에서 현재 지역 정산 데이터를 삭제하고 있습니다: area=$area',
          progress: 0.26,
        );
        await billState.clearAreaCache(area);
        trace.log(
          '정산 삭제 검증 완료: area=$area general=${await localRepository.countGeneralBills(area)} regular=${await localRepository.countRegularBills(area)}',
          progress: 0.30,
        );

        trace.log(
          'SQLite에서 현재 지역 섹터 데이터를 삭제하고 있습니다: area=$area',
          progress: 0.34,
        );
        await sectorState.clearAreaCache(area);
        trace.log(
          '섹터 삭제 검증 완료: area=$area remaining=${await localRepository.countSectors(area)}',
          progress: 0.38,
        );

        if (division.isNotEmpty) {
          trace.log(
            'SQLite에서 현재 지역 업무 규칙을 삭제하고 있습니다: division=$division area=$area',
            progress: 0.40,
          );
          await ruleState.clearAreaCache(division: division, area: area);
          trace.log(
            '업무 규칙 삭제 검증 완료: division=$division area=$area remaining=${await localRepository.countRules(division: division, area: area)}',
            progress: 0.41,
          );
        } else {
          trace.log(
            '업무 규칙 SQLite 삭제를 건너뜁니다: reason=division_empty area=$area',
            progress: 0.41,
          );
        }

        trace.log(
          'SQLite에서 현재 지역 운영 메타 정보를 초기화하고 있습니다: area=$area',
          progress: 0.42,
        );
        await _clearOperationalMetadata(
          localRepository: localRepository,
          area: area,
        );

        trace.log(
          'Firestore에서 최신 주차 구역 데이터를 내려받고 있습니다: area=$area',
          progress: 0.54,
        );
        await locationState.manualLocationRefreshStrictForArea(area);
        final locationMeta = await localRepository.readAreaMeta(area);
        trace.log(
          '주차 구역 SQLite 저장 완료: area=$area count=${locationMeta?.locationCount ?? 0} totalCapacity=${locationMeta?.totalCapacity ?? 0}',
          progress: 0.62,
        );

        if (hasBillCapability) {
          trace.log(
            '최신 정산 타입 데이터를 내려받아 로컬에 저장하고 있습니다.',
            progress: 0.66,
          );
          await billState.manualBillRefreshStrictForArea(area);
          trace.log(
            '정산 SQLite 저장 완료: area=$area general=${await localRepository.countGeneralBills(area)} regular=${await localRepository.countRegularBills(area)}',
            progress: 0.70,
          );
        } else {
          trace.log(
            '현재 지역에 bill 기능이 없어 정산 로컬 다운로드를 건너뜁니다.',
            progress: 0.66,
          );
        }

        if (hasSectorCapability) {
          trace.log(
            '최신 섹터 데이터를 내려받아 로컬에 저장하고 있습니다.',
            progress: 0.72,
          );
          trace.log(
            '섹터 캐시의 항목 형식과 지역 범위를 검증할 준비를 하고 있습니다.',
            progress: 0.75,
          );
          final sectorCount =
              await sectorState.manualSectorRefreshStrictForArea(area);
          trace.log(
            '섹터 SQLite 무결성 검증 완료: area=$area count=$sectorCount checks=fields,area,duplicateId,duplicateName,date,state',
            progress: 0.79,
          );
        } else {
          trace.log(
            '현재 지역에 sector 기능이 없어 섹터 로컬 다운로드를 건너뜁니다.',
            progress: 0.78,
          );
        }

        if (hasRuleCapability) {
          if (division.isEmpty) {
            throw StateError('업무 규칙을 내려받을 회사 정보가 없습니다.');
          }
          trace.log(
            '최신 업무 규칙 데이터를 내려받아 로컬에 저장하고 있습니다.',
            progress: 0.81,
          );
          final ruleFound = await ruleState.manualRuleRefreshStrictForArea(
            division: division,
            area: area,
          );
          final localRule = await localRepository.readRule(
            division: division,
            area: area,
          );
          trace.log(
            '업무 규칙 SQLite 무결성 검증 완료: division=$division area=$area found=$ruleFound localCount=${await localRepository.countRules(division: division, area: area)} todos=${localRule?.todoItems.length ?? 0} contentLength=${localRule?.content.length ?? 0}',
            progress: 0.83,
          );
        } else {
          trace.log(
            '현재 지역에 rule 기능이 없어 업무 규칙 로컬 다운로드를 건너뜁니다.',
            progress: 0.83,
          );
        }

        if (areaState.currentArea.trim() != area) {
          throw StateError('동기화 중 현재 지역이 변경되었습니다.');
        }

        trace.log(
          'Single 정책에 따라 월정기 존재 여부를 별도 조회하지 않고 unknown으로 유지합니다.',
          progress: 0.88,
        );

        final syncedAtIso = DateTime.now().toIso8601String();
        trace.log('새 운영 메타 정보를 저장하고 검증하고 있습니다.', progress: 0.94);
        await _saveOperationalMetadata(
          localRepository: localRepository,
          area: area,
          syncedAtIso: syncedAtIso,
        );
        final finalMeta = await localRepository.readAreaMeta(area);
        trace.log('운영 메타 정보 저장 완료: $syncedAtIso', progress: 0.97);
        trace.log(
          'SQLite snapshot 검증 완료: area=$area locations=${finalMeta?.locationCount ?? 0} generalBills=${finalMeta?.generalBillCount ?? 0} regularBills=${finalMeta?.regularBillCount ?? 0} sectors=${finalMeta?.sectorCount ?? 0} rules=${division.isEmpty ? 0 : await localRepository.countRules(division: division, area: area)} monthly=${finalMeta?.hasMonthlyParking} monthlyPolicy=unknown_without_plate syncedAt=${finalMeta?.syncedAt?.toIso8601String()}',
          progress: 0.99,
        );
        dataSaved = true;

        if (trace.developerMode) {
          await trace.succeed(
            '현재 지역 capability에 맞는 운영 데이터 동기화가 완료되었습니다. 개발자 모드에서는 앱을 종료하지 않습니다.',
          );
          return SingleOperationalDataSyncResult.completed;
        }

        await trace.succeed('현재 지역 capability에 맞는 운영 데이터 동기화가 완료되었습니다.');

        if (!rootContext.mounted) {
          throw StateError('완료 안내 화면을 표시할 수 없습니다.');
        }

        Widget completionDialog(BuildContext dialogContext) {
          final reduceMotion =
              MediaQuery.maybeOf(dialogContext)?.disableAnimations ?? false;
          return AlertDialog(
            title: Row(
              children: <Widget>[
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.82, end: 1),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 360),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: const Icon(Icons.check_circle_rounded),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text('운영 데이터 동기화 완료')),
              ],
            ),
            content: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              child: Text(
                '현재 지역 $area의 기존 SQLite 운영 데이터를 삭제하고 최신 데이터로 다시 저장했습니다.\n\n변경 사항 적용을 위해 앱을 종료합니다. 앱을 다시 실행해 주세요.',
                key: ValueKey<String>(area),
              ),
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

        if (useCommonUi) {
          await showCommonOverlayDialog<void>(
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
            useCommonUi: useCommonUi,
          );
        }
        return SingleOperationalDataSyncResult.completed;
      } catch (error, stackTrace) {
        if (!dataSaved) {
          trace.log('실패 후 주차 구역 캐시를 정리하고 있습니다.');
          try {
            await locationState.clearAreaCache(area);
          } catch (cleanupError) {
            trace.log('주차 구역 캐시 정리 실패: $cleanupError');
          }

          trace.log('실패 후 정산 데이터 캐시를 정리하고 있습니다.');
          try {
            await billState.clearAreaCache(area);
          } catch (cleanupError) {
            trace.log('정산 데이터 캐시 정리 실패: $cleanupError');
          }

          trace.log('실패 후 섹터 데이터 캐시를 정리하고 있습니다.');
          try {
            await sectorState.clearAreaCache(area);
          } catch (cleanupError) {
            trace.log('섹터 데이터 캐시 정리 실패: $cleanupError');
          }

          if (division.isNotEmpty) {
            trace.log('실패 후 업무 규칙 캐시를 정리하고 있습니다.');
            try {
              await ruleState.clearAreaCache(division: division, area: area);
            } catch (cleanupError) {
              trace.log('업무 규칙 캐시 정리 실패: $cleanupError');
            }
          }

          trace.log('실패 후 운영 메타 정보를 정리하고 있습니다.');
          try {
            await _clearOperationalMetadata(
              localRepository: localRepository,
              area: area,
            );
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
            useCommonUi: useCommonUi,
          );
        }
        return SingleOperationalDataSyncResult.failed;
      }
    } finally {
      _running = false;
    }
  }

  static Future<void> _clearOperationalMetadata({
    required OperationalLocalRepository localRepository,
    required String area,
  }) async {
    await localRepository.clearOperationalMetadata(area);
    final meta = await localRepository.readAreaMeta(area);
    if (meta?.hasMonthlyParking != null || meta?.syncedAt != null) {
      throw StateError('기존 운영 데이터 SQLite 메타 정보 삭제 검증 실패');
    }
  }

  static Future<void> _saveOperationalMetadata({
    required OperationalLocalRepository localRepository,
    required String area,
    required String syncedAtIso,
  }) async {
    await localRepository.saveOperationalMetadata(
      area: area,
      hasMonthlyParking: null,
      syncedAtIso: syncedAtIso,
    );
    final meta = await localRepository.readAreaMeta(area);
    if (meta?.hasMonthlyParking != null ||
        meta?.syncedAt?.toIso8601String() != syncedAtIso) {
      throw StateError('운영 데이터 SQLite 메타 정보 저장 검증 실패');
    }
  }

  static void _showFailure(
    BuildContext context,
    String message, {
    required bool useCommonUi,
  }) {
    if (useCommonUi) {
      showFailedSnackbar(context, message, useCommonUi: true);
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
