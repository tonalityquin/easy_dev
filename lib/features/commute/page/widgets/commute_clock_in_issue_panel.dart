import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import 'parkinworkin_windows_desktop.dart';

enum CommuteClockInIssueState {
  available,
  resolving,
  success,
  failure,
}

class CommuteClockInIssueConsoleSection extends StatelessWidget {
  const CommuteClockInIssueConsoleSection({
    super.key,
    required this.state,
    required this.reduceMotion,
    required this.onRetry,
    required this.onClockInAgain,
  });

  final CommuteClockInIssueState state;
  final bool reduceMotion;
  final Future<void> Function() onRetry;
  final Future<void> Function() onClockInAgain;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 170);

    return Semantics(
      liveRegion: true,
      container: true,
      label: _semanticsLabel,
      child: AnimatedSize(
        duration: duration,
        curve: CommonUiMotion.standard,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: duration,
          reverseDuration: duration,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: CommonUiMotion.enter,
              reverseCurve: CommonUiMotion.exit,
            );
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.025),
              end: Offset.zero,
            ).animate(curved);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: _buildState(context, tokens),
        ),
      ),
    );
  }

  String get _semanticsLabel {
    return switch (state) {
      CommuteClockInIssueState.available =>
        '오늘 출근 기록이 이미 있습니다. 출근 상태를 정리할 수 있습니다',
      CommuteClockInIssueState.resolving => '출근 상태를 정리하고 있습니다',
      CommuteClockInIssueState.success =>
        '출근 상태 정리가 완료되었습니다. 다시 출근할 수 있습니다',
      CommuteClockInIssueState.failure =>
        '출근 상태를 정리하지 못했습니다. 다시 시도할 수 있습니다',
    };
  }

  Widget _buildState(BuildContext context, CommonUiTokens tokens) {
    final statusColor = switch (state) {
      CommuteClockInIssueState.available => tokens.warning,
      CommuteClockInIssueState.resolving => tokens.brandPrimary,
      CommuteClockInIssueState.success => tokens.success,
      CommuteClockInIssueState.failure => tokens.danger,
    };
    final detail = switch (state) {
      CommuteClockInIssueState.available => '오늘 출근 기록이 이미 있습니다.',
      CommuteClockInIssueState.resolving => '오늘 기기의 출근 상태를 정리하고 있습니다.',
      CommuteClockInIssueState.success => '오늘 기기의 출근 상태를 정리했습니다.',
      CommuteClockInIssueState.failure => '오늘 기기의 출근 상태를 정리하지 못했습니다.',
    };
    final status = switch (state) {
      CommuteClockInIssueState.available => 'RESET AVAILABLE',
      CommuteClockInIssueState.resolving => 'CLEARING',
      CommuteClockInIssueState.success => 'RESOLVED',
      CommuteClockInIssueState.failure => 'FAILED',
    };
    final next = switch (state) {
      CommuteClockInIssueState.available => '상태를 정리한 뒤 다시 출근할 수 있습니다.',
      CommuteClockInIssueState.resolving => '처리가 완료될 때까지 잠시 기다려 주세요.',
      CommuteClockInIssueState.success => '다시 출근을 진행해 주세요.',
      CommuteClockInIssueState.failure => '잠시 후 다시 시도해 주세요.',
    };

    return Column(
      key: ValueKey<CommuteClockInIssueState>(state),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParkinWorkinConsoleRow(
          label: 'DETAIL',
          value: detail,
          reduceMotion: reduceMotion,
          valueColor: tokens.textSecondary,
          valueFontWeight: FontWeight.w600,
        ),
        const SizedBox(height: 8),
        ParkinWorkinConsoleRow(
          label: 'STATUS',
          reduceMotion: reduceMotion,
          value: status,
          valueColor: statusColor,
          trailing: state == CommuteClockInIssueState.resolving
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: statusColor,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 8),
        ParkinWorkinConsoleRow(
          label: 'NEXT',
          value: next,
          reduceMotion: reduceMotion,
          valueColor: tokens.textPrimary,
          valueFontWeight: FontWeight.w600,
        ),
        if (state != CommuteClockInIssueState.resolving) ...[
          const SizedBox(height: 4),
          ParkinWorkinConsoleAction(
            reduceMotion: reduceMotion,
            attentionToken: 'clock_in_issue_${state.name}',
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => unawaited(
                  state == CommuteClockInIssueState.success
                      ? onClockInAgain()
                      : onRetry(),
                ),
                icon: Icon(
                  switch (state) {
                    CommuteClockInIssueState.available => Icons.build_outlined,
                    CommuteClockInIssueState.success => Icons.play_arrow_rounded,
                    CommuteClockInIssueState.failure => Icons.refresh_rounded,
                    CommuteClockInIssueState.resolving => Icons.sync_rounded,
                  },
                  size: 18,
                ),
                label: Text(
                  switch (state) {
                    CommuteClockInIssueState.available => '출근 이슈 해결',
                    CommuteClockInIssueState.success => '다시 출근하기',
                    CommuteClockInIssueState.failure => '다시 시도',
                    CommuteClockInIssueState.resolving => '',
                  },
                ),
                style: TextButton.styleFrom(
                  foregroundColor: state == CommuteClockInIssueState.failure
                      ? tokens.danger
                      : tokens.brandPrimary,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
