import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/ops_delayed_refresh_gate.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/area_remote_settings/application/local_area_capability_refresh.dart';
import '../../../account/applications/user_state.dart';
import '../../../dev/application/area_state.dart';
import '../area/area_master_cache.dart';

class HeadquarterAreaMasterDownloadOutcome {
  const HeadquarterAreaMasterDownloadOutcome({
    required this.status,
    this.areaCount = 0,
    this.downloadedAtIso = '',
  });

  final HeadquarterAreaMasterDownloadStatus status;
  final int areaCount;
  final String downloadedAtIso;
}

enum HeadquarterAreaMasterDownloadStatus {
  completed,
  cancelled,
  failed,
  missingDivision,
  missingCurrentArea,
}

class HeadquarterAreaMasterDownloadWorkflow {
  const HeadquarterAreaMasterDownloadWorkflow._();

  static Future<HeadquarterAreaMasterDownloadOutcome> run({
    required BuildContext context,
    String source = 'headquarter_quick_actions_side_dock',
    bool useCommonUi = true,
  }) async {
    final userState = context.read<UserState>();
    final areaState = context.read<AreaState>();
    final division = userState.division.trim();
    final currentArea = userState.currentArea.trim();
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '본사 데이터 내려받기',
      initialMessage: '본사 데이터 내려받기 요청을 확인하고 있습니다.',
      useCommonUi: useCommonUi,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );

    trace.log('download_source=$source', progress: 0.03);

    if (division.isEmpty) {
      const failureMessage = '회사 정보가 없어 본사 데이터를 내려받을 수 없습니다.';
      await trace.fail(failureMessage);
      if (!trace.developerMode && context.mounted) {
        showFailedSnackbar(context, failureMessage, useCommonUi: useCommonUi);
      }
      return const HeadquarterAreaMasterDownloadOutcome(
        status: HeadquarterAreaMasterDownloadStatus.missingDivision,
      );
    }

    if (currentArea.isEmpty) {
      const failureMessage = '현재 지역 정보가 없어 본사 데이터를 내려받을 수 없습니다.';
      await trace.fail(failureMessage);
      if (!trace.developerMode && context.mounted) {
        showFailedSnackbar(context, failureMessage, useCommonUi: useCommonUi);
      }
      return const HeadquarterAreaMasterDownloadOutcome(
        status: HeadquarterAreaMasterDownloadStatus.missingCurrentArea,
      );
    }

    trace.log('회사 정보를 확인했습니다: $division', progress: 0.06);
    trace.log('현재 로그인 지역을 확인했습니다: $currentArea', progress: 0.1);
    trace.log('내려받기 실행 게이트를 확인하고 있습니다.', progress: 0.14);

    final shouldRefresh = await OpsDelayedRefreshGate.waitIfNeeded(
      context: context,
      title: '본사 데이터 내려받기',
      message: '본사 데이터를 내려받기 전 요청을 준비하고 있습니다.',
      useCommonUi: useCommonUi,
    );
    if (!shouldRefresh) {
      await trace.succeed('사용자가 본사 데이터 내려받기를 취소했습니다.');
      return const HeadquarterAreaMasterDownloadOutcome(
        status: HeadquarterAreaMasterDownloadStatus.cancelled,
      );
    }

    try {
      trace.log(
        '현재 근무 회사의 전체 지역 정보를 내려받고 있습니다.',
        progress: 0.2,
      );
      final snapshot = await AreaMasterCache.refreshDivision(
        division,
        requiredArea: currentArea,
        onLog: trace.log,
        progressStart: 0.22,
        progressEnd: 0.76,
      );
      trace.log(
        '지역 Snapshot 저장을 확인했습니다: division=${snapshot.division} areas=${snapshot.items.length} downloadedAt=${snapshot.refreshedAtIso}',
        progress: 0.78,
      );

      AreaMasterItem? currentItem;
      for (final item in snapshot.items) {
        if (item.name.trim() == currentArea) {
          currentItem = item;
          break;
        }
      }
      if (currentItem == null) {
        throw StateError(
          '내려받은 데이터에서 현재 지역을 찾을 수 없습니다: $currentArea',
        );
      }

      final capabilityRefresh = await LocalAreaCapabilityRefresh.refresh(
        areaState: areaState,
        division: division,
        area: currentArea,
        source: 'headquarter_quick_download',
        onLog: trace.log,
        progressStart: 0.8,
        progressEnd: 0.9,
        requireSnapshot: true,
      );
      trace.log(
        '현재 지역 capability 반영을 확인했습니다: snapshot=${capabilityRefresh.snapshotKeys} areaState=${capabilityRefresh.afterKeys} changed=${capabilityRefresh.changed} remoteRead=0 remoteWrite=0',
        progress: 0.91,
      );
      trace.log(
        '현재 지역 연결 정보를 확인했습니다: emailPresent=${currentItem.email.trim().isNotEmpty} invitePresent=${currentItem.invite.trim().isNotEmpty} communicationPresent=${currentItem.communication.trim().isNotEmpty}',
        progress: 0.94,
      );
      trace.log(
        '회사 전체 지역 Snapshot 교체와 현재 지역 반영을 완료했습니다.',
        progress: 0.99,
      );

      await trace.succeed(
        '본사 데이터 내려받기가 완료되었습니다: areas=${snapshot.items.length}',
      );

      if (!trace.developerMode && context.mounted) {
        await _showCompletionDialog(
          context: context,
          areaCount: snapshot.items.length,
          downloadedAtIso: snapshot.refreshedAtIso,
        );
      }

      return HeadquarterAreaMasterDownloadOutcome(
        status: HeadquarterAreaMasterDownloadStatus.completed,
        areaCount: snapshot.items.length,
        downloadedAtIso: snapshot.refreshedAtIso,
      );
    } catch (error, stackTrace) {
      const failureMessage = '본사 데이터 내려받기에 실패했습니다.';
      await trace.fail(
        failureMessage,
        error: error,
        stackTrace: stackTrace,
      );
      if (!trace.developerMode && context.mounted) {
        showFailedSnackbar(
          context,
          failureMessage,
          useCommonUi: useCommonUi,
        );
      }
      return const HeadquarterAreaMasterDownloadOutcome(
        status: HeadquarterAreaMasterDownloadStatus.failed,
      );
    }
  }

  static Future<void> _showCompletionDialog({
    required BuildContext context,
    required int areaCount,
    required String downloadedAtIso,
  }) {
    return showCommonDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        final text = Theme.of(dialogContext).textTheme;
        final reduceMotion =
            MediaQuery.maybeOf(dialogContext)?.disableAnimations ?? false;
        final content = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : CommonUiMotion.component,
                    curve: CommonUiMotion.enter,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tokens.successContainer,
                      borderRadius: BorderRadius.circular(
                        CommonUiShapes.control,
                      ),
                    ),
                    child: Icon(
                      Icons.download_done_rounded,
                      color: tokens.onSuccessContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '본사 데이터 내려받기 완료',
                      style: text.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.component,
                curve: CommonUiMotion.enter,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tokens.surfaceOverlay,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Text(
                  '$areaCount개 지역 정보를 최신 상태로 업데이트했습니다.\n\n기준 시각: $downloadedAtIso',
                  style: text.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CommonButton(
                label: '확인',
                icon: Icons.check_rounded,
                expand: true,
                haptic: CommonHaptic.selection,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );

        if (reduceMotion) return content;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: CommonUiMotion.layout,
          curve: CommonUiMotion.enter,
          child: content,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: Transform.scale(
                  scale: 0.98 + (0.02 * value),
                  child: child,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
