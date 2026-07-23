import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import 'personal_prompt_components.dart';

class PersonalVehicleTimeline extends StatelessWidget {
  const PersonalVehicleTimeline({
    super.key,
    required this.plate,
  });

  final PlateModel plate;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final steps = _steps(plate);
    final logs = List<PlateLogModel>.of(
      plate.logs ?? const <PlateLogModel>[],
    )..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '진행 내역',
                style: textTheme.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            PersonalPromptStatusPill(
              label: _statusLabel(plate.typeEnum),
              foreground: _statusForeground(tokens, plate.typeEnum),
              background: _statusBackground(tokens, plate.typeEnum),
            ),
          ],
        ),
        const SizedBox(height: 10),
        PersonalPromptPanel(
          child: Column(
            children: steps
                .asMap()
                .entries
                .map(
                  (entry) => PromptAnimatedReveal(
                    key: ValueKey<String>(entry.value.title),
                    delay: Duration(milliseconds: entry.key * 32),
                    child: _TimelineStepRow(step: entry.value),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        if (logs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            '최근 로그',
            style: textTheme.titleSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...logs.take(4).toList().asMap().entries.map(
                (entry) => PromptAnimatedReveal(
                  key: ValueKey<String>(
                    '${entry.value.timestamp.microsecondsSinceEpoch}-${entry.key}',
                  ),
                  delay: Duration(milliseconds: entry.key * 28),
                  child: _LogRow(log: entry.value),
                ),
              ),
        ],
      ],
    );
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.title,
    required this.timeLabel,
    required this.active,
    required this.done,
  });

  final String title;
  final String timeLabel;
  final bool active;
  final bool done;
}

class _TimelineStepRow extends StatelessWidget {
  const _TimelineStepRow({required this.step});

  final _TimelineStep step;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final color = step.done || step.active
        ? tokens.statusSynchronized
        : tokens.iconDisabled;
    final background = step.done || step.active
        ? tokens.statusSynchronizedContainer
        : tokens.surfaceDisabled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          AnimatedContainer(
            duration: personalPromptDuration(
              context,
              PromptUiMotion.selection,
            ),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(.26)),
            ),
            child: AnimatedSwitcher(
              duration: personalPromptDuration(
                context,
                PromptUiMotion.selection,
              ),
              child: Icon(
                step.done
                    ? Icons.check_rounded
                    : step.active
                        ? Icons.radio_button_checked_rounded
                        : Icons.circle_outlined,
                key: ValueKey<String>(
                  '${step.done}-${step.active}',
                ),
                color: color,
                size: 17,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.title,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            step.timeLabel,
            style: textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log});

  final PlateLogModel log;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final title = log.action.trim().isEmpty
        ? '${log.from} → ${log.to}'
        : log.action.trim();

    return PersonalPromptPanel(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.history_rounded,
            color: tokens.statusMonthlyParking,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${log.from} → ${log.to}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDateTime(log.timestamp),
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

List<_TimelineStep> _steps(PlateModel plate) {
  final type = plate.typeEnum;
  final request = _formatDateTime(plate.requestTime);
  final updated = _formatDateTime(plate.updatedAt ?? plate.requestTime);

  return <_TimelineStep>[
    _TimelineStep(
      title: '입차 요청',
      timeLabel: request,
      active: type == PlateType.parkingRequests,
      done: type == PlateType.parkingCompleted ||
          type == PlateType.departureRequests ||
          type == PlateType.departureCompleted,
    ),
    _TimelineStep(
      title: '입차 완료',
      timeLabel: type == PlateType.parkingCompleted ||
              type == PlateType.departureRequests ||
              type == PlateType.departureCompleted
          ? updated
          : '-',
      active: type == PlateType.parkingCompleted,
      done: type == PlateType.departureRequests ||
          type == PlateType.departureCompleted,
    ),
    _TimelineStep(
      title: '출차 요청',
      timeLabel: type == PlateType.departureRequests ||
              type == PlateType.departureCompleted
          ? updated
          : '-',
      active: type == PlateType.departureRequests,
      done: type == PlateType.departureCompleted,
    ),
    _TimelineStep(
      title: '출차 완료',
      timeLabel: type == PlateType.departureCompleted ? updated : '-',
      active: type == PlateType.departureCompleted,
      done: type == PlateType.departureCompleted,
    ),
  ];
}

String _statusLabel(PlateType? type) {
  switch (type) {
    case PlateType.parkingRequests:
      return '입차 진행 중';
    case PlateType.parkingCompleted:
      return '주차 중';
    case PlateType.departureRequests:
      return '출차 요청됨';
    case PlateType.departureCompleted:
      return '출차 완료';
    case null:
      return '정보 없음';
  }
}

Color _statusForeground(PromptUiTokens tokens, PlateType? type) {
  switch (type) {
    case PlateType.parkingRequests:
      return tokens.statusSettlementPending;
    case PlateType.parkingCompleted:
      return tokens.statusParkingCompleted;
    case PlateType.departureRequests:
      return tokens.statusDepartureRequested;
    case PlateType.departureCompleted:
      return tokens.statusSynchronized;
    case null:
      return tokens.statusOffline;
  }
}

Color _statusBackground(PromptUiTokens tokens, PlateType? type) {
  switch (type) {
    case PlateType.parkingRequests:
      return tokens.statusSettlementPendingContainer;
    case PlateType.parkingCompleted:
      return tokens.statusParkingCompletedContainer;
    case PlateType.departureRequests:
      return tokens.statusDepartureRequestedContainer;
    case PlateType.departureCompleted:
      return tokens.statusSynchronizedContainer;
    case null:
      return tokens.statusOfflineContainer;
  }
}

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = dt.toLocal();
  return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
