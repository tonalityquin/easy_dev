import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/selector/application/dev_auth.dart';
import 'firebase_activity_monitor.dart';

class FirebaseActivityStatusDialog {
  const FirebaseActivityStatusDialog._();

  static Future<void> show(BuildContext context) async {
    if (!DevAuth.devModeEnabled.value || !context.mounted) return;
    final reduced = MediaQuery.of(context).disableAnimations;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Firebase 활동 센터 닫기',
      barrierColor: Colors.black54,
      transitionDuration:
          reduced ? Duration.zero : const Duration(milliseconds: 240),
      pageBuilder: (context, _, __) => const _FirebaseActivityDashboard(),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FirebaseActivityDashboard extends StatefulWidget {
  const _FirebaseActivityDashboard();

  @override
  State<_FirebaseActivityDashboard> createState() =>
      _FirebaseActivityDashboardState();
}

class _FirebaseActivityDashboardState
    extends State<_FirebaseActivityDashboard> {
  final FirebaseActivityMonitor monitor = FirebaseActivityMonitor.instance;
  static const Map<String, String> _filters = <String, String>{
    'all': '전체',
    'read': '읽기',
    'snapshot': 'Snapshot',
    'create': '생성',
    'update': '수정',
    'set': 'set/upsert',
    'delete': '삭제',
    'write': '쓰기 전체',
    'batch': 'Batch',
    'transaction': 'Transaction',
  };
  static const Map<String, String> _statusFilters = <String, String>{
    'all': '모든 상태',
    'running': '현재 진행',
    'completed': '완료',
    'failed': '실패',
    'received': '수신',
  };

  String _filter = 'all';
  String _statusFilter = 'all';
  bool _copiedFilter = false;
  int? _copiedEventSequence;
  final Set<int> _expandedSequences = <int>{};

  Future<void> _copyFilter(Iterable<FirebaseActivityEvent> events) async {
    if (!DevAuth.devModeEnabled.value) return;
    final code = monitor.debugPrintCodeFor(
      events,
      typeFilter: _filter,
      statusFilter: _statusFilter,
    );
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted || !DevAuth.devModeEnabled.value) return;
    setState(() {
      _copiedFilter = true;
      _copiedEventSequence = null;
    });
  }

  Future<void> _copyEvent(FirebaseActivityEvent event) async {
    if (!DevAuth.devModeEnabled.value) return;
    final code = monitor.debugPrintCodeForEvent(event);
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted || !DevAuth.devModeEnabled.value) return;
    setState(() {
      _copiedEventSequence = event.sequence;
      _copiedFilter = false;
    });
  }

  Widget _metric(
    BuildContext context,
    String label,
    int count,
    IconData icon,
    Color color,
    Duration duration,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 136,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          AnimatedSwitcher(
            duration: duration,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              '$count',
              key: ValueKey<int>(count),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Color _eventColor(FirebaseActivityEvent event) {
    if (event.phase == FirebaseActivityPhase.failed) {
      return const Color(0xFFE65D67);
    }
    if (event.createCommands > 0 ||
        event.kind == FirebaseActivityKind.create) {
      return const Color(0xFF43BD99);
    }
    if (event.deleteCommands > 0 ||
        event.kind == FirebaseActivityKind.delete) {
      return const Color(0xFFF47C8D);
    }
    if (event.updateCommands > 0 ||
        event.kind == FirebaseActivityKind.update) {
      return const Color(0xFFFFB45E);
    }
    if (event.kind == FirebaseActivityKind.read) {
      return const Color(0xFF559AF2);
    }
    return const Color(0xFF43B6B2);
  }

  String _commandText(FirebaseActivityEvent event) {
    if (event.documentCommands == 0) {
      if (event.phase != FirebaseActivityPhase.completed) return '';
      switch (event.kind) {
        case FirebaseActivityKind.set:
          return '성공한 set/upsert 명령 1건';
        case FirebaseActivityKind.create:
          return '성공한 생성 분류 명령 1건';
        case FirebaseActivityKind.update:
          return '성공한 수정 명령 1건';
        case FirebaseActivityKind.delete:
          return '성공한 삭제 명령 1건';
        default:
          return '';
      }
    }
    final prefix = switch (event.phase) {
      FirebaseActivityPhase.completed => '성공한 문서 명령',
      FirebaseActivityPhase.failed => '실패한 시도의 예정 명령',
      FirebaseActivityPhase.started => '아직 확정되지 않은 예정 명령',
      FirebaseActivityPhase.received => '수신된 명령 정보',
    };
    final commands = <String>[
      if (event.setCommands > 0) 'set ${event.setCommands}',
      if (event.createCommands > 0) '생성 분류 ${event.createCommands}',
      if (event.updateCommands > 0) '수정 ${event.updateCommands}',
      if (event.deleteCommands > 0) '삭제 ${event.deleteCommands}',
    ].join(' · ');
    return '$prefix $commands';
  }

  String _phaseLabel(FirebaseActivityEvent event) => switch (event.phase) {
        FirebaseActivityPhase.started =>
          monitor.isOperationRunning(event.operationId) ? '현재 진행' : '시작 이력',
        FirebaseActivityPhase.completed => '완료',
        FirebaseActivityPhase.received => '수신',
        FirebaseActivityPhase.failed => '실패',
      };

  Widget _eventRow(
    BuildContext context,
    FirebaseActivityEvent event,
    Duration duration,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = _expandedSequences.contains(event.sequence);
    final copied = _copiedEventSequence == event.sequence;
    final commandText = _commandText(event);
    return Padding(
      key: ValueKey<int>(event.sequence),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant.withAlpha(120)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() {
                      if (expanded) {
                        _expandedSequences.remove(event.sequence);
                      } else {
                        _expandedSequences.add(event.sequence);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            event.phase == FirebaseActivityPhase.failed
                                ? Icons.error_outline_rounded
                                : event.phase == FirebaseActivityPhase.completed
                                    ? Icons.check_circle_outline_rounded
                                    : event.phase == FirebaseActivityPhase.started
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.adjust_rounded,
                            size: 18,
                            color: _eventColor(event),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '${event.kind.name} · ${_phaseLabel(event)}'
                                  '${event.operationId == null ? '' : ' · #${event.operationId}'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  event.source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                if (commandText.isNotEmpty)
                                  Text(
                                    commandText,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 19,
                            color: scheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: copied ? '이 이벤트 복사됨' : '이 이벤트 debugPrint 복사',
                  onPressed: () => _copyEvent(event),
                  icon: AnimatedSwitcher(
                    duration: duration,
                    child: Icon(
                      copied ? Icons.check_rounded : Icons.copy_rounded,
                      key: ValueKey<bool>(copied),
                      size: 18,
                      color: copied ? const Color(0xFF43BD99) : scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: duration,
              alignment: Alignment.topCenter,
              curve: Curves.easeInOutCubic,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Divider(color: scheme.outlineVariant),
                          if (event.parentOperationId != null)
                            Text(
                              '상위 작업 #${event.parentOperationId}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          if (event.durationMs != null)
                            Text(
                              '소요 시간 ${event.durationMs}ms',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          if (event.attempts > 0)
                            Text(
                              'Transaction 시도 ${event.attempts}회',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          if (event.kind == FirebaseActivityKind.snapshot)
                            Text(
                              '변경 추가 ${event.added} · 수정 ${event.modified} · 제거 ${event.removed}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          if (event.fromCache != null)
                            Text(
                              '캐시 ${event.fromCache} · 로컬 미확정 ${event.pendingWrites ?? false}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          const SizedBox(height: 6),
                          SelectableText(
                            monitor.debugPrintCodeForEvent(event),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduced = media.disableAnimations;
    final duration = reduced ? Duration.zero : const Duration(milliseconds: 220);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: DevAuth.devModeEnabled,
      builder: (context, developer, _) {
        if (!developer) {
          return Dialog(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('개발자 모드가 종료되었습니다.'),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('닫기'),
                  ),
                ],
              ),
            ),
          );
        }
        return AnimatedBuilder(
          animation: monitor,
          builder: (context, _) {
            final Iterable<FirebaseActivityEvent> sourceEvents =
                _statusFilter == 'running'
                    ? monitor.runningOperations.reversed
                    : monitor.events.reversed;
            final events = sourceEvents
                .where((event) => event.matchesFilter(_filter))
                .where((event) => event.matchesStatusFilter(
                      _statusFilter,
                      isRunning: monitor.isOperationRunning(event.operationId),
                    ))
                .toList(growable: false);
            final completedRows = events
                .where((event) => event.phase == FirebaseActivityPhase.completed)
                .length;
            final failedRows = events
                .where((event) => event.phase == FirebaseActivityPhase.failed)
                .length;
            final receivedRows = events
                .where((event) => event.phase == FirebaseActivityPhase.received)
                .length;
            final activeRows = events
                .where((event) =>
                    event.phase == FirebaseActivityPhase.started &&
                    monitor.isOperationRunning(event.operationId))
                .length;
            final active = monitor.activeOperationCount;
            final idle = monitor.isIdle && active == 0;
            return Dialog(
              clipBehavior: Clip.antiAlias,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 620,
                  maxHeight: math.max(
                    260.0,
                    media.size.height - media.padding.vertical - 36.0,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.monitor_heart_outlined,
                            color: idle
                                ? scheme.outline
                                : const Color(0xFF43BD99),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Firebase 활동 센터',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                AnimatedSwitcher(
                                  duration: duration,
                                  child: Text(
                                    idle
                                        ? '대기 · 진행 중 0건'
                                        : '활동 중 · 진행 중 $active건',
                                    key: ValueKey<String>('$idle:$active'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: idle
                                              ? scheme.outline
                                              : const Color(0xFF43BD99),
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '닫기',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  _metric(
                                    context,
                                    '상위 완료',
                                    monitor.topLevelCompletedCount,
                                    Icons.timeline_rounded,
                                    scheme.primary,
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    '내부 완료',
                                    monitor.nestedCompletedCount,
                                    Icons.account_tree_outlined,
                                    scheme.primary,
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    '읽기 호출',
                                    monitor.count(FirebaseActivityKind.read),
                                    Icons.download_rounded,
                                    const Color(0xFF559AF2),
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    'Snapshot 수신',
                                    monitor.snapshotCount,
                                    Icons.waves_rounded,
                                    const Color(0xFF43BD99),
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    'set/upsert 성공 명령',
                                    monitor.setCount,
                                    Icons.file_copy_outlined,
                                    const Color(0xFFFFB45E),
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    '종류 미분류 쓰기 완료',
                                    monitor.count(FirebaseActivityKind.write),
                                    Icons.drive_file_rename_outline,
                                    scheme.primary,
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    '생성 분류 성공 명령',
                                    monitor.createCount,
                                    Icons.add_circle_outline,
                                    const Color(0xFF43BD99),
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    '수정 성공 명령',
                                    monitor.updateCount,
                                    Icons.edit_outlined,
                                    const Color(0xFFFFB45E),
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    '삭제 성공 명령',
                                    monitor.deleteCount,
                                    Icons.delete_outline,
                                    const Color(0xFFF47C8D),
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    'Batch 커밋',
                                    monitor.count(FirebaseActivityKind.batch),
                                    Icons.layers_outlined,
                                    scheme.primary,
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    'Transaction 완료',
                                    monitor.count(FirebaseActivityKind.transaction),
                                    Icons.sync_rounded,
                                    scheme.primary,
                                    duration,
                                  ),
                                  _metric(
                                    context,
                                    '실패 이벤트',
                                    monitor.failureCount,
                                    Icons.error_outline,
                                    const Color(0xFFE65D67),
                                    duration,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '상단 완료·수신 합계 ${monitor.totalActivityCount}회'
                                ' = 상위 완료 ${monitor.topLevelCompletedCount}회'
                                ' + Snapshot ${monitor.snapshotCount}회',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '분류 가능 성공 문서 명령 ${monitor.documentCommandCount}건'
                                ' · 캐시 Snapshot ${monitor.cacheSnapshotCount}회'
                                ' · 로컬 미확정 Snapshot ${monitor.localSnapshotCount}회',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '관측된 조회 결과 ${monitor.readResultDocumentCount}문서(중복·캐시 가능)'
                                ' · 캐시 조회 ${monitor.cacheReadResponseCount}회'
                                ' · 변경 추가 ${monitor.snapshotAddedCount}'
                                ' / 수정 ${monitor.snapshotModifiedCount}'
                                ' / 제거 ${monitor.snapshotRemovedCount}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (active > 0) ...<Widget>[
                                const SizedBox(height: 12),
                                Text(
                                  '진행 중 요청 ($active)',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                for (final running in monitor.runningOperations.take(12))
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      children: <Widget>[
                                        const Icon(
                                          Icons.hourglass_top_rounded,
                                          size: 16,
                                          color: Color(0xFF43BD99),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '#${running.operationId} · '
                                            '${running.kind.name} · ${running.source}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (active > 12)
                                  Text(
                                    '그 외 ${active - 12}건 진행 중',
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                              ],
                              const SizedBox(height: 12),
                              Text(
                                '활동 이력 · ${_filters[_filter]} · '
                                '${_statusFilters[_statusFilter]}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '선택된 이벤트 ${events.length}행 · 완료 $completedRows행 '
                                '· 실패 $failedRows행 · 수신 $receivedRows행 '
                                '· 현재 진행 $activeRows건',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '작업 유형',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: <Widget>[
                                    for (final entry in _filters.entries)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: ChoiceChip(
                                          label: Text(entry.value),
                                          selected: _filter == entry.key,
                                          onSelected: (_) => setState(() {
                                            _filter = entry.key;
                                            _copiedFilter = false;
                                            _copiedEventSequence = null;
                                          }),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '진행 상태',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: <Widget>[
                                    for (final entry in _statusFilters.entries)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: ChoiceChip(
                                          label: Text(entry.value),
                                          selected: _statusFilter == entry.key,
                                          onSelected: (_) => setState(() {
                                            _statusFilter = entry.key;
                                            _copiedFilter = false;
                                            _copiedEventSequence = null;
                                          }),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (events.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Text(
                                    _statusFilter == 'running'
                                        ? '현재 진행 중인 해당 유형의 요청이 없습니다.'
                                        : '해당 유형·상태의 최근 기록이 없습니다.',
                                  ),
                                ),
                              for (final event in events.take(80))
                                _eventRow(context, event, duration),
                              if (events.length > 80)
                                Text(
                                  '최근 80행 표시 · 복사에는 현재 필터의 ${events.length}행이 포함됩니다.',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              const SizedBox(height: 8),
                              Text(
                                '유형과 진행 상태는 독립적으로 필터링합니다. '
                                '시작 이력은 현재 진행 요청과 다르며, 실패한 시도의 예정 명령은 성공 건수에 포함되지 않습니다. '
                                '선택된 이벤트 행 수와 앱 시작 이후 누적 명령 수는 서로 다릅니다. '
                                '일반 쓰기 호출 중 명령 유형을 알 수 없는 경우는 문서 명령 합계에서 제외합니다. '
                                '조회·Snapshot에는 캐시 및 재시도 결과가 포함될 수 있습니다. '
                                '실제 Firebase 청구 건수나 금액은 아닙니다.',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _copyFilter(events.reversed),
                        icon: Icon(
                          _copiedFilter
                              ? Icons.check_rounded
                              : Icons.copy_rounded,
                        ),
                        label: Text(
                          _copiedFilter
                              ? '현재 유형·상태 debugPrint 복사됨'
                              : '현재 유형·상태 debugPrint 복사',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
