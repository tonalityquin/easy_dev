import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/selector/application/dev_auth.dart';
import 'firebase_activity_meter.dart';
import 'firebase_activity_journal.dart';

class FirebaseActivityCenterDialog extends StatefulWidget {
  const FirebaseActivityCenterDialog({super.key});

  static Future<void> open(BuildContext context) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!context.mounted) return;
    if (!enabled) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('상세 활동 기록은 개발자 모드 ON에서 확인할 수 있습니다.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => const FirebaseActivityCenterDialog(),
    );
  }

  @override
  State<FirebaseActivityCenterDialog> createState() =>
      _FirebaseActivityCenterDialogState();
}

class _FirebaseActivityCenterDialogState
    extends State<FirebaseActivityCenterDialog> {
  String _filter = 'all';
  bool _copying = false;
  bool _archiveView = false;
  String _sessionSelection = 'current';
  String _periodSelection = 'all';
  int _page = 0;
  final List<FirebaseActivityJournalCursor?> _pageCursors =
      <FirebaseActivityJournalCursor?>[null];
  late Future<List<String>> _sessionsFuture;
  late Future<FirebaseActivityJournalPage> _archiveFuture;
  late Future<FirebaseActivityJournalCost> _costFuture;
  DateTime? _selectedSince;

  DateTime? get _since {
    if (_periodSelection == '15m') {
      return DateTime.now().subtract(const Duration(minutes: 15));
    }
    if (_periodSelection == '1h') {
      return DateTime.now().subtract(const Duration(hours: 1));
    }
    return null;
  }

  String? get _requestedSessionId => _sessionSelection == 'current' ||
          _sessionSelection == 'all'
      ? null
      : _sessionSelection;

  void _reloadArchive() {
    final meter = FirebaseActivityMeter.instance;
    final since = _since;
    setState(() {
      _page = 0;
      _pageCursors
        ..clear()
        ..add(null);
      _selectedSince = since;
      _sessionsFuture = meter.journalSessions();
      _archiveFuture = meter.journal.readPage(
        requestedSessionId: _requestedSessionId,
        allSessions: _sessionSelection == 'all',
        service: _filter,
        since: since,
      );
      _costFuture = meter.journal.readCost(
        requestedSessionId: _requestedSessionId,
        allSessions: _sessionSelection == 'all',
        since: since,
      );
    });
  }

  void _goToPage(int page, FirebaseActivityJournalCursor? cursor) {
    if (page < 0) return;
    final meter = FirebaseActivityMeter.instance;
    setState(() {
      _page = page;
      if (_pageCursors.length <= page) {
        _pageCursors.add(cursor);
      }
      _archiveFuture = meter.journal.readPage(
        cursor: _pageCursors[page],
        requestedSessionId: _requestedSessionId,
        allSessions: _sessionSelection == 'all',
        service: _filter,
        since: _selectedSince,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    DevAuth.devModeEnabled.addListener(_checkDeveloperMode);
    final meter = FirebaseActivityMeter.instance;
    _sessionsFuture = meter.journalSessions();
    _archiveFuture = meter.journal.readPage();
    _costFuture = meter.journal.readCost();
    if (!DevAuth.devModeEnabled.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkDeveloperMode());
    }
  }

  void _checkDeveloperMode() {
    if (mounted && !DevAuth.devModeEnabled.value) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _copy() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      if (!DevAuth.devModeEnabled.value ||
          !await DevAuth.isDevModeEnabled() || !mounted) return;
      final meter = FirebaseActivityMeter.instance;
      final text = _filter == 'cost'
          ? meter.exportJournalCostCode(
              await _costFuture,
              requestedSessionId: _requestedSessionId,
              since: _selectedSince,
              allSessions: _sessionSelection == 'all',
            )
          : await meter.exportJournalCode(
              service: _filter,
              requestedSessionId: _requestedSessionId,
              allSessions: _sessionSelection == 'all',
              since: _selectedSince,
            );
      if (!mounted || !DevAuth.devModeEnabled.value ||
          !await DevAuth.isDevModeEnabled()) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        await HapticFeedback.selectionClick();
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('선택한 보관 범위의 debugPrint 코드를 복사했습니다.')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('클립보드 복사 실패: ${error.runtimeType}')),
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Widget _buildArchive() {
    return FutureBuilder<FirebaseActivityJournalPage>(
      key: const ValueKey<String>('firebase_journal_archive'),
      future: _archiveFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(child: Text('보관 기록을 읽을 수 없습니다.'));
        }
        final archive = snapshot.data!;
        if (_page < _pageCursors.length &&
            _pageCursors[_page] == null &&
            archive.startCursor != null) {
          _pageCursors[_page] = archive.startCursor;
        }
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        return AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: Column(
            key: ValueKey<String>(
              '$_page-$_sessionSelection-$_periodSelection-$_filter',
            ),
            children: [
            Text(
              '현재 페이지 ${archive.lines.length}건 · ${_page + 1}페이지 · '
              '누락 ${archive.droppedEvents}건 · 정리된 파일 ${archive.droppedFiles}개 · '
              '저장 오류 ${archive.writeErrors}건',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '최신 기록',
                  onPressed: _page > 0
                      ? () => _goToPage(_page - 1, _pageCursors[_page - 1])
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text('${_page + 1}${archive.hasMore ? ' · 이전 기록 있음' : ''}'),
                IconButton(
                  tooltip: '이전 기록',
                  onPressed: archive.hasMore
                      ? () => _goToPage(_page + 1, archive.nextCursor)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Expanded(
              child: archive.lines.isEmpty
                  ? const Center(child: Text('선택한 범위에 보관된 기록이 없습니다.'))
                  : ListView.builder(
                      itemCount: archive.lines.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SelectableText(
                          archive.lines[index],
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
            ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_checkDeveloperMode);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meter = FirebaseActivityMeter.instance;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final media = MediaQuery.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: media.size.height * 0.84,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.query_stats_rounded, size: 21),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('FIREBASE ACTIVITY CENTER',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              ValueListenableBuilder<FirebaseActivitySummary>(
                valueListenable: meter.summary,
                builder: (context, totals, _) => AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: Wrap(
                    key: ValueKey<int>(totals.eventCount),
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _summaryLabel('READ', totals.read),
                      _summaryLabel('WRITE', totals.write),
                      _summaryLabel('DELETE', totals.delete),
                      _summaryLabel('SNAP', totals.snap),
                      _summaryLabel('LISTEN', totals.activeListeners),
                      _summaryLabel('STORAGE', totals.storage),
                      _summaryLabel('AGG', totals.aggregation),
                      _summaryLabel('TX', totals.transaction),
                      _summaryLabel('BATCH', totals.batch),
                      _summaryLabel('ERROR', totals.errors),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<FirebaseActivitySummary>(
                valueListenable: meter.summary,
                builder: (context, activity, _) => Text(
                  '업로드 ${activity.uploadBytes}B · '
                  '다운로드 ${activity.downloadBytes}B · '
                  '관측된 이벤트 ${activity.eventCount}건',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      value: _filter,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('전체 활동')),
                        DropdownMenuItem(value: 'firestore', child: Text('Firestore')),
                        DropdownMenuItem(value: 'storage', child: Text('Storage / GCS')),
                        DropdownMenuItem(value: 'realtime', child: Text('Realtime LISTEN / SNAP')),
                        DropdownMenuItem(value: 'optimization', child: Text('비용 최적화·생략')),
                        DropdownMenuItem(value: 'cost', child: Text('비용 영향·관측 한계')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _filter = value);
                          _reloadArchive();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _copying ? null : () => unawaited(_copy()),
                    icon: _copying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('debugPrint 코드 복사'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FutureBuilder<List<String>>(
                    future: _sessionsFuture,
                    builder: (context, snapshot) {
                      final sessions = snapshot.data ?? <String>[];
                      final selected = _sessionSelection == 'current' ||
                              _sessionSelection == 'all' ||
                              sessions.contains(_sessionSelection)
                          ? _sessionSelection
                          : 'current';
                      return DropdownButton<String>(
                        value: selected,
                        items: <DropdownMenuItem<String>>[
                          const DropdownMenuItem(value: 'current', child: Text('현재 세션')),
                          const DropdownMenuItem(value: 'all', child: Text('모든 보관 세션')),
                          for (final id in sessions)
                            if (id != meter.sessionId)
                              DropdownMenuItem(
                                value: id,
                                child: Text('이전 세션 $id', overflow: TextOverflow.ellipsis),
                              ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _sessionSelection = value;
                            _archiveView = true;
                          });
                          _reloadArchive();
                        },
                      );
                    },
                  ),
                  DropdownButton<String>(
                    value: _periodSelection,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('전체 시간')),
                      DropdownMenuItem(value: '15m', child: Text('최근 15분')),
                      DropdownMenuItem(value: '1h', child: Text('최근 1시간')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _periodSelection = value;
                        _archiveView = true;
                      });
                      _reloadArchive();
                    },
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _archiveView = !_archiveView);
                      if (_archiveView) _reloadArchive();
                    },
                    icon: Icon(_archiveView ? Icons.bolt_rounded : Icons.history_rounded),
                    label: Text(_archiveView ? '실시간 500개' : '보관 기록'),
                  ),
                  IconButton(
                    tooltip: '보관 기록 새로고침',
                    onPressed: _reloadArchive,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  _filter == 'cost'
                      ? 'COST는 앱 관측값과 청구 확인 불가 항목을 분리합니다.'
                      : _filter == 'optimization'
                          ? '생략 이벤트는 실제 Firestore READ·WRITE 사용량에 합산하지 않습니다.'
                          : '메인 앱의 계측 이벤트입니다. 포그라운드 Plate TTS는 제외됩니다.',
                  key: ValueKey<String>(_filter),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 4),
              const Divider(),
              Expanded(
                child: ValueListenableBuilder<FirebaseActivitySummary>(
                  valueListenable: meter.summary,
                  builder: (context, _, __) {
                    if (_filter == 'cost') {
                      return FutureBuilder<FirebaseActivityJournalCost>(
                        future: _costFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError || !snapshot.hasData) {
                            return const Center(child: Text('COST 기록을 읽을 수 없습니다.'));
                          }
                          final report = snapshot.data!;
                          return TweenAnimationBuilder<double>(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            tween: Tween<double>(begin: 0, end: 1),
                            builder: (context, opacity, child) =>
                                Opacity(opacity: opacity, child: child),
                            child: _buildCostAnalysis(
                              meter.costFromJournal(report),
                              report,
                            ),
                          );
                        },
                      );
                    }
                    if (_archiveView) {
                      return AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        child: _buildArchive(),
                      );
                    }
                    final events = meter.events
                        .where((event) => _filter == 'all' ||
                          event.service == _filter ||
                          (_filter == 'realtime' &&
                            (event.operation.startsWith('LISTEN') ||
                             event.operation == 'SNAP' ||
                             event.operation == 'REMOTE_LISTEN_CLEANUP')))
                        .toList(growable: false);
                    if (events.isEmpty) {
                      return const Center(child: Text('관측된 Firebase 활동이 없습니다.'));
                    }
                    return ListView.builder(
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${event.operation} · ${event.result} · '
                                  '${event.elapsedMs}ms',
                                  style: Theme.of(context).textTheme.labelMedium),
                              const SizedBox(height: 2),
                              SelectableText(event.line,
                                  style: Theme.of(context).textTheme.bodySmall),
                              const Divider(height: 12),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '관측된 호출·스냅샷·트랜잭션·전송량이며 확정 청구량은 아닙니다. '
                '인덱스·Rules·저장 용량·서버 동작·다른 기기 및 포그라운드 Plate TTS의 비용은 포함되지 않을 수 있습니다.',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCostAnalysis(
    FirebaseCostSummary cost,
    FirebaseActivityJournalCost report,
  ) {
    return ListView(
      key: const ValueKey<String>('firebase_cost_analysis'),
      children: [
        Text(
          '보관 세션 ${report.sessionCount}개 · 관측 ${report.totalEvents}건 · '
          '구조화 이전 기록 ${report.legacyEvents}건',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (report.incomplete)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '불완전한 보관 집계: 기존 스키마·삭제·저장 실패·저널 상태로 '
              '일부 수치가 누락될 수 있습니다. 0은 미계측의 증거가 아닙니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        _costSection('OBSERVED · 선택 범위의 앱 관측값', cost.observed),
        _costSection('ESTIMATED · 추정과 조건', cost.estimated),
        _costSection('UNAVAILABLE · 미계측 항목', cost.unavailable),
      ],
    );
  }

  Widget _costSection(String title, List<String> lines) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SelectableText(
                line,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const Divider(height: 16),
        ],
      ),
    );
  }

  Widget _summaryLabel(String name, int value) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$name $value', style: const TextStyle(fontSize: 11)),
    );
  }
}
