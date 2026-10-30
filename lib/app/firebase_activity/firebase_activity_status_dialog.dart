import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/selector/application/dev_auth.dart';
import 'firebase_activity_monitor.dart';
import 'firebase_activity_cost_estimator.dart';
import 'firebase_activity_billing_config.dart';

enum _DashboardView { counter, action, all }

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
    'cancelled': '미제출·준비 표시 만료',
    'unknown': '결과 미확정',
  };

  _DashboardView _view = _DashboardView.counter;
  String _filter = 'all';
  String _statusFilter = 'all';
  bool _copiedFilter = false;
  bool _copiedAll = false;
  bool _copiedCost = false;
  String? _copiedEventLine;
  final Set<int> _expandedSequences = <int>{};
  final Set<int> _expandedActionIds = <int>{};

  Future<bool> _copyCode(String code, String scope) async {
    if (!DevAuth.devModeEnabled.value) return false;
    try {
      await Clipboard.setData(ClipboardData(text: code));
    } catch (error) {
      if (DevAuth.devModeEnabled.value) {
        debugPrint(
          '[FIREBASE_ACTIVITY] clipboardCopyFailed scope=$scope error=${error.runtimeType}',
        );
      }
      return false;
    }
    if (!mounted || !DevAuth.devModeEnabled.value) return false;
    debugPrint(
      '[FIREBASE_ACTIVITY] clipboardCopied scope=$scope characters=${code.length}',
    );
    return true;
  }

  Future<void> _copyFilter(Iterable<FirebaseActivityEvent> events) async {
    if (!DevAuth.devModeEnabled.value) return;
    final code = monitor.debugPrintCodeFor(
      events,
      typeFilter: _filter,
      statusFilter: _statusFilter,
    );
    if (!await _copyCode(code, 'filtered')) return;
    setState(() {
      _copiedFilter = true;
      _copiedAll = false;
      _copiedEventLine = null;
    });
  }

  Future<void> _copyEvent(FirebaseActivityEvent event) async {
    if (!await _copyCode(monitor.debugPrintCodeForEvent(event), 'event')) {
      return;
    }
    setState(() {
      _copiedEventLine = event.debugLine;
      _copiedFilter = false;
      _copiedAll = false;
    });
  }

  Future<void> _copyCounter(
    Iterable<FirebaseActivityEvent> selected,
  ) async {
    if (!await _copyCode(
      monitor.debugPrintCodeForCounterIncrements(selected),
      'counter',
    )) {
      return;
    }
    setState(() {
      _copiedFilter = true;
      _copiedAll = false;
      _copiedEventLine = null;
    });
  }

  Future<void> _copyActions(
    Iterable<FirebaseActivityAction> selected,
  ) async {
    if (!await _copyCode(monitor.debugPrintCodeForActions(selected), 'actions')) {
      return;
    }
    setState(() {
      _copiedFilter = true;
      _copiedAll = false;
      _copiedEventLine = null;
    });
  }

  Future<void> _copyAll() async {
    if (!await _copyCode(monitor.debugPrintCode, 'all')) return;
    setState(() {
      _copiedAll = true;
      _copiedFilter = false;
      _copiedEventLine = null;
    });
  }

  Future<void> _copyCost() async {
    if (!await _copyCode(monitor.costDebugPrintCode, 'cost')) return;
    setState(() {
      _copiedCost = true;
      _copiedAll = false;
      _copiedFilter = false;
      _copiedEventLine = null;
    });
  }

  Widget _costOverview(BuildContext context, Duration duration) {
    final scheme = Theme.of(context).colorScheme;
    final cost = monitor.cost;
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeInOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary.withAlpha(100)),
        color: scheme.primaryContainer.withAlpha(60),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('앱 관측 예상 사용요금',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Text(
                  FirebaseActivityCostEstimator.formatWon(cost.totalWon),
                  key: ValueKey<String>(cost.totalWon.toStringAsFixed(8)),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${FirebaseActivityBillingConfig.editionLabel} · '
            '${FirebaseActivityBillingConfig.region} · '
            'USD 1 = ₩${FirebaseActivityBillingConfig.krwPerUsd.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Text(
            '${FirebaseActivityBillingConfig.priceReference} · '
            '${FirebaseActivityBillingConfig.exchangeRateReference}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          for (final row in cost.summaries)
            if (row.units > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(row.label,
                        style: Theme.of(context).textTheme.bodySmall)),
                    Text('${row.units} 단위',
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(width: 12),
                    Text(FirebaseActivityCostEstimator.formatWon(row.won),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
          const SizedBox(height: 6),
          Text('관측 문서 크기 ${cost.knownBytes}B · 필드 ${cost.knownFields}개 · '
              '불확실성 포함 ${cost.uncertainOperations}건',
              style: Theme.of(context).textTheme.labelSmall),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('요금 설정: ${FirebaseActivityBillingConfig.confidenceLabel} · '
                    '기준 ${FirebaseActivityBillingConfig.pricingDate}',
                    style: Theme.of(context).textTheme.labelSmall),
                if (cost.possibleExtraUnits > 0)
                  Text('제거 원인 불명의 추가 읽기 가능성: '
                      '${cost.possibleExtraUnits}단위 · '
                      '${FirebaseActivityCostEstimator.formatWon(cost.possibleExtraWon)} 범위',
                      style: Theme.of(context).textTheme.labelSmall),
                Text('원인 미확정 제거 ${cost.unknownRemoved}건 · '
                    '재연결 재조회 후보 ${cost.reconnectCandidates}회 · '
                    '메타데이터 변경 ${cost.metadataOnlyEvents}회',
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '실제 청구액이 아닙니다. 무료 할당량, 색인 읽기, 보안 규칙 읽기, '
            '전체 데이터 보관·전송 비용 및 미계측 작업은 포함되지 않거나 '
            '불완전하게 추정됩니다. 현재 앱 세션의 관측값입니다.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _counterRow(
    BuildContext context,
    FirebaseActivityEvent event,
    Duration duration,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey<String>('counter_${event.sequence}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.add_circle_outline_rounded,
                      color: colorScheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${event.counterBefore} → ${event.counterAfter} · '
                      'Firestore ${event.kind.name} 완료',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _copyEvent(event),
                    tooltip: 'debugPrint 코드 복사',
                    icon: AnimatedSwitcher(
                      duration: duration,
                      child: Icon(
                        _copiedEventLine == event.debugLine
                            ? Icons.check_rounded
                            : Icons.copy_rounded,
                        key: ValueKey<bool>(_copiedEventLine == event.debugLine),
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '#${event.sequence} · ${event.timestamp.toLocal().toIso8601String()}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(event.source, style: Theme.of(context).textTheme.bodySmall),
              Text(
                event.actionName == null
                    ? '자동 실행 · 행동 미연결'
                    : '${event.actionName} · 행동 #${event.actionId}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionRow(
    BuildContext context,
    FirebaseActivityAction action,
    Duration duration,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = _expandedActionIds.contains(action.id);
    final related = monitor.events
        .where((event) => event.actionId == action.id)
        .toList(growable: false);
    return Padding(
      key: ValueKey<String>('action_${action.id}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            ListTile(
              onTap: () => setState(() {
                if (expanded) {
                  _expandedActionIds.remove(action.id);
                } else {
                  _expandedActionIds.add(action.id);
                }
              }),
              title: Text('${action.name} · #${action.id}'),
              subtitle: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                ),
                child: Text(
                  '${action.startedAt.toLocal().toIso8601String()} · '
                  '${action.outcomeLabel} · '
                  '보존된 이벤트 ${related.length}건',
                  key: ValueKey<String>('${action.id}_${action.outcome.name}'),
                ),
              ),
              trailing: Icon(expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded),
            ),
            AnimatedSize(
              duration: duration,
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (action.issueCodes.isNotEmpty)
                            Text('상태 코드 ${action.issueCodes.join(', ')}',
                                style: Theme.of(context).textTheme.bodySmall),
                          for (final event in related)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text(
                                '#${event.sequence} · ${event.timestamp.toLocal().toIso8601String()} · '
                                '${event.source} · ${event.phase.name}'
                                '${event.increasedCounter ? ' · 카운터 ${event.counterBefore} → ${event.counterAfter}' : ''}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _copyActions(<FirebaseActivityAction>[action]),
                              icon: const Icon(Icons.copy_rounded),
                              label: const Text('debugPrint 코드 복사'),
                            ),
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
    if (event.phase == FirebaseActivityPhase.failed ||
        event.phase == FirebaseActivityPhase.outcomeUnknown) {
      return const Color(0xFFE65D67);
    }
    if (event.phase == FirebaseActivityPhase.cancelled) {
      return const Color(0xFF929BAB);
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
      FirebaseActivityPhase.outcomeUnknown => '결과 미확정 명령',
      FirebaseActivityPhase.started => '아직 확정되지 않은 예정 명령',
      FirebaseActivityPhase.received => '수신된 명령 정보',
      FirebaseActivityPhase.cancelled => '미제출·표시 종료된 예정 명령',
    };
    final commands = <String>[
      if (event.setCommands > 0) 'set ${event.setCommands}',
      if (event.createCommands > 0) '생성 분류 ${event.createCommands}',
      if (event.updateCommands > 0) '수정 ${event.updateCommands}',
      if (event.deleteCommands > 0) '삭제 ${event.deleteCommands}',
    ].join(' · ');
    return '$prefix $commands';
  }

  String _outcomeBasisLabel(String basis) => switch (basis) {
        'non_write_error' => '쓰기 외 요청 오류',
        'sdk_confirmed_rejection' => 'SDK의 확정 거부 응답',
        'local_invocation_rejection' => 'SDK Future 반환 전 로컬 거부',
        'sdk_future_not_returned' => 'SDK Future 반환 전 예외 · 서버 결과 검증 불가',
        'sdk_timeout_unverified' => 'SDK 요청 시간 초과 · 결과 미확정',
        'sdk_error_unverified' => 'SDK 오류 · 반영 여부 미확정',
        'async_error_unverified' => '비동기 오류 · 반영 여부 미확정',
        _ => '분류 근거 확인 필요',
      };

  String _stageLabel(FirebaseActivityEvent event) => switch (event.stage) {
        FirebaseActivityStage.preparing => '명령 준비 중',
        FirebaseActivityStage.submitting => '커밋 제출 중',
        FirebaseActivityStage.attempting => '트랜잭션 시도 ${event.attempts > 0 ? event.attempts : 1}',
        FirebaseActivityStage.retrying => '트랜잭션 재시도 ${event.attempts}',
        FirebaseActivityStage.callerTimedOut => '호출자 시간 초과 · 원본 응답 확인 중',
        FirebaseActivityStage.stalePreparation => '미제출 Batch 준비 표시 만료',
        null => '실행 중',
      };

  String _phaseLabel(FirebaseActivityEvent event) => switch (event.phase) {
        FirebaseActivityPhase.started =>
          monitor.isOperationRunning(event.operationId)
              ? _stageLabel(event)
              : '시작 이력',
        FirebaseActivityPhase.completed => '완료',
        FirebaseActivityPhase.received => '수신',
        FirebaseActivityPhase.failed => '실패',
        FirebaseActivityPhase.outcomeUnknown => '결과 미확정',
        FirebaseActivityPhase.cancelled =>
            event.stage == FirebaseActivityStage.stalePreparation
                ? '준비 표시 만료'
                : '미제출 중단',
      };

  Widget _eventRow(
    BuildContext context,
    FirebaseActivityEvent event,
    Duration duration,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = _expandedSequences.contains(event.sequence);
    final copied = _copiedEventLine == event.debugLine;
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
                            (event.phase == FirebaseActivityPhase.failed ||
                                event.phase == FirebaseActivityPhase.outcomeUnknown)
                                ? Icons.error_outline_rounded
                                : event.phase == FirebaseActivityPhase.completed
                                    ? Icons.check_circle_outline_rounded
                                    : event.phase == FirebaseActivityPhase.started
                                        ? Icons.radio_button_checked_rounded
                                        : event.phase == FirebaseActivityPhase.cancelled
                                            ? Icons.block_rounded
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
                                  AnimatedSwitcher(
                                    duration: duration,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(begin: 0.97, end: 1)
                                            .animate(animation),
                                        child: child,
                                      ),
                                    ),
                                    child: Text(
                                      commandText,
                                      key: ValueKey<String>(
                                        '${event.operationId}:${event.attempts}:${event.stage}:$commandText',
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.labelSmall,
                                    ),
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
                          if (event.stage != null)
                            Text(
                              '현재 단계 ${_stageLabel(event)} · 예정 명령 ${event.documentCommands}건',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          if (event.callState != null)
                            AnimatedSwitcher(
                              duration: duration,
                              child: Text(
                                event.callState == FirebaseActivityCallState.sdkFutureReturned
                                    ? 'SDK 호출 Future 확보 · 서버 반영 여부는 결과 응답으로 판정'
                                    : 'SDK 호출 Future 확보 전',
                                key: ValueKey<FirebaseActivityCallState>(event.callState!),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          if (event.outcomeBasis != null)
                            AnimatedSwitcher(
                              duration: duration,
                              child: Text(
                                '결과 분류 근거 ${_outcomeBasisLabel(event.outcomeBasis!)}',
                                key: ValueKey<String>(event.outcomeBasis!),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          if (event.attempts > 0)
                            Text(
                              'Transaction 시도 ${event.attempts}회',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          if (event.estimatedUnits > 0)
                            Text(
                              '과금 추정 ${event.estimatedUnits}단위 · '
                              '${FirebaseActivityCostEstimator.formatWon(event.estimatedWon)}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          if (event.dataBytes > 0)
                            Text(
                              '관측 데이터 ${event.dataBytes}B · 필드 ${event.fieldCount}개',
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
                    : monitor.events.reversed.map((event) =>
                        event.phase == FirebaseActivityPhase.started
                            ? monitor.runningEventFor(event.operationId) ?? event
                            : event);
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
            final unknownRows = events
                .where((event) => event.phase == FirebaseActivityPhase.outcomeUnknown)
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
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: <Widget>[
                                    for (final entry in const <_DashboardView, String>{
                                      _DashboardView.counter: '카운터 증가 원인',
                                      _DashboardView.action: '행동별 기록',
                                      _DashboardView.all: '전체 활동',
                                    }.entries)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: ChoiceChip(
                                          label: Text(entry.value),
                                          selected: _view == entry.key,
                                          onSelected: (_) => setState(() {
                                            _view = entry.key;
                                            _copiedFilter = false;
                                            _copiedAll = false;
                                            _copiedEventLine = null;
                                          }),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              _costOverview(context, duration),
                              const SizedBox(height: 12),
                              if (_view == _DashboardView.counter) ...<Widget>[
                                AnimatedSwitcher(
                                  duration: duration,
                                  transitionBuilder: (child, animation) => FadeTransition(
                                    opacity: animation,
                                    child: SizeTransition(
                                      sizeFactor: animation,
                                      axisAlignment: -1,
                                      child: child,
                                    ),
                                  ),
                                  child: Text(
                                    'Firestore 완료 ${monitor.firestoreOperationCount}회 · 보존 ${monitor.counterIncrements.length}회 · 이전 기록 ${monitor.omittedCounterIncrements}회',
                                    key: ValueKey<int>(monitor.firestoreOperationCount),
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (monitor.counterIncrements.isEmpty)
                                  const Text('카운터 증가 기록이 없습니다.'),
                                for (final event in monitor.counterIncrements.toList().reversed.take(80))
                                  _counterRow(context, event, duration),
                                if (monitor.counterIncrements.length > 80)
                                  Text(
                                    '최근 80행 표시 · 복사는 보존된 ${monitor.counterIncrements.length}행 전체',
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                              ],
                              if (_view == _DashboardView.action) ...<Widget>[
                                Text(
                                  '행동 기록 ${monitor.actions.length}건',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                if (monitor.actions.isEmpty)
                                  const Text('연결된 행동 기록이 없습니다.'),
                                for (final action in monitor.actions.toList().reversed.take(80))
                                  _actionRow(context, action, duration),
                                if (monitor.actions.length > 80)
                                  Text(
                                    '최근 80개 행동 표시 · 복사는 보존된 ${monitor.actions.length}개 행동 전체',
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                              ],
                              if (_view == _DashboardView.all) ...<Widget>[
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
                                '상단 Firestore 완료 ${monitor.firestoreOperationCount}회 · '
                                '전체 상위 완료·Snapshot 수신 합계 ${monitor.totalActivityCount}회'
                                ' = 상위 완료 ${monitor.topLevelCompletedCount}회'
                                ' + Snapshot ${monitor.snapshotCount}회',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '초기화 완료 ${monitor.count(FirebaseActivityKind.initialization)}회 · '
                                '인증 완료 ${monitor.count(FirebaseActivityKind.authentication)}회 · '
                                'Storage 완료 ${monitor.count(FirebaseActivityKind.storage)}회',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '응답 미확정 ${monitor.unknownOutcomeCount}회 · 미제출 중단 ${monitor.abandonedBatchCount}회 · 준비 표시 만료 ${monitor.stalePreparationCount}회',
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
                                  '진행 중 요청 ($active · 상위 ${monitor.topLevelActiveOperationCount} · 내부 ${monitor.nestedActiveOperationCount})',
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
                                            '${running.kind.name} · ${_stageLabel(running)} · '
                                            '예정 set ${running.setCommands} / 생성 ${running.createCommands} / '
                                            '수정 ${running.updateCommands} / 삭제 ${running.deleteCommands} · '
                                            '${running.source}',
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
                                '· 실패 $failedRows행 · 미확정 $unknownRows행 · 수신 $receivedRows행 '
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
                                            _copiedAll = false;
                                            _copiedEventLine = null;
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
                                            _copiedAll = false;
                                            _copiedEventLine = null;
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
                                '진행 중 Batch·Transaction의 문서 명령은 예정 수이며 커밋 성공 전에는 누적 성공 수에 포함되지 않습니다. '
                                '준비 중이던 Batch는 명시적인 중단 또는 일정 시간 명령이 없을 때 표시를 종료하며, 이후 실제 커밋 성공과는 별도로 구분합니다. '
                                '유형과 진행 상태는 독립적으로 필터링합니다. '
                                '시작 이력은 현재 진행 요청과 다르며, 실패하거나 결과 미확정인 예정 명령은 성공 건수에 포함되지 않습니다. '
                                '선택된 이벤트 행 수와 앱 시작 이후 누적 명령 수는 서로 다릅니다. '
                                '일반 쓰기 호출 중 명령 유형을 알 수 없는 경우는 문서 명령 합계에서 제외합니다. '
                                '조회·Snapshot에는 캐시 및 재시도 결과가 포함될 수 있습니다. '
                                '호출자의 시간 초과는 원본 커밋 실패를 뜻하지 않으며, 최종 응답은 별도로 집계됩니다. '
                                'SDK Future 반환은 서버 반영의 증거가 아니며, 확정 거부가 아닌 오류는 결과 미확정으로 분류합니다. '
                                '개별 이벤트를 펼치면 SDK 호출 단계와 결과 분류 근거를 확인하고 debugPrint 코드로 복사할 수 있습니다. '
                                '실제 Firebase 청구 건수나 금액은 아닙니다.',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedSize(
                        duration: duration,
                        curve: Curves.easeInOutCubic,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            FilledButton.icon(
                              onPressed: () {
                                if (_view == _DashboardView.counter) {
                                  _copyCounter(monitor.counterIncrements);
                                } else if (_view == _DashboardView.action) {
                                  _copyActions(monitor.actions);
                                } else {
                                  _copyFilter(events.reversed);
                                }
                              },
                              icon: AnimatedSwitcher(
                                duration: duration,
                                child: Icon(
                                  _copiedFilter
                                      ? Icons.check_rounded
                                      : Icons.copy_rounded,
                                  key: ValueKey<bool>(_copiedFilter),
                                ),
                              ),
                              label: Text(
                                _copiedFilter
                                    ? '현재 탭 debugPrint 코드 복사됨'
                                    : '현재 탭 debugPrint 코드 복사',
                              ),
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: _copyCost,
                              icon: AnimatedSwitcher(
                                duration: duration,
                                child: Icon(
                                  _copiedCost
                                      ? Icons.check_rounded
                                      : Icons.receipt_long_outlined,
                                  key: ValueKey<bool>(_copiedCost),
                                ),
                              ),
                              label: Text(_copiedCost
                                  ? '비용 debugPrint 코드 복사됨'
                                  : '비용 debugPrint 코드 복사'),
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: _copyAll,
                              icon: AnimatedSwitcher(
                                duration: duration,
                                child: Icon(
                                  _copiedAll
                                      ? Icons.check_rounded
                                      : Icons.content_copy_rounded,
                                  key: ValueKey<bool>(_copiedAll),
                                ),
                              ),
                              label: Text(
                                _copiedAll
                                    ? '전체 debugPrint 코드 복사됨'
                                    : '전체 debugPrint 코드 복사',
                              ),
                            ),
                          ],
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
