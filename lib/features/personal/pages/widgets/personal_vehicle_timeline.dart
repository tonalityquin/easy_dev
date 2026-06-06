import 'package:flutter/material.dart';

import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';

class PersonalVehicleTimeline extends StatelessWidget {
  const PersonalVehicleTimeline({
    super.key,
    required this.plate,
  });

  final PlateModel plate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final steps = _steps(plate);
    final logs = List<PlateLogModel>.of(plate.logs ?? const <PlateLogModel>[])
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '진행 내역',
          style: text.titleSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        ...steps.map((step) => _TimelineStepRow(step: step)),
        if (logs.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '최근 로그',
            style: text.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ...logs.take(4).map((log) => _LogRow(log: log)),
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
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = step.done || step.active ? cs.primary : cs.outline;
    final bg = step.done || step.active ? cs.primaryContainer : cs.surfaceContainerHigh;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              step.done ? Icons.check_rounded : step.active ? Icons.radio_button_checked_rounded : Icons.circle_outlined,
              color: color,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.title,
              style: text.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            step.timeLabel,
            style: text.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
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
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final title = log.action.trim().isEmpty ? '${log.from} → ${log.to}' : log.action.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, color: cs.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${log.from} → ${log.to}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDateTime(log.timestamp),
            style: text.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
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
      done: type == PlateType.parkingCompleted || type == PlateType.departureRequests || type == PlateType.departureCompleted,
    ),
    _TimelineStep(
      title: '입차 완료',
      timeLabel: type == PlateType.parkingCompleted || type == PlateType.departureRequests || type == PlateType.departureCompleted ? updated : '-',
      active: type == PlateType.parkingCompleted,
      done: type == PlateType.departureRequests || type == PlateType.departureCompleted,
    ),
    _TimelineStep(
      title: '출차 요청',
      timeLabel: type == PlateType.departureRequests || type == PlateType.departureCompleted ? updated : '-',
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

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = dt.toLocal();
  return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
