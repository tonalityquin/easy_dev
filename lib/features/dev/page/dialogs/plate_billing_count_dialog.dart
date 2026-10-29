import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/firebase_activity/firebase_activity_status_dialog.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../selector/application/dev_auth.dart';
import '../../../../shared/plate/domain/services/plate_billing_count_service.dart';
import '../../data/repositories/plate_billing_count_repository.dart';
import '../../domain/models/plate_billing_count_model.dart';

Future<void> showPlateBillingCountDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const PlateBillingCountDialog(),
  );
}

class PlateBillingCountDialog extends StatefulWidget {
  const PlateBillingCountDialog({super.key});

  @override
  State<PlateBillingCountDialog> createState() => _PlateBillingCountDialogState();
}

class _PlateBillingCountDialogState extends State<PlateBillingCountDialog> {
  final PlateBillingCountRepository _repository = PlateBillingCountRepository();
  late DateTime _selectedMonth;
  late Future<List<PlateBillingCountModel>> _rowsFuture;
  int _reloadKey = 0;
  bool _deleting = false;
  double _deleteProgress = 0;

  Duration get _motionDuration =>
      MediaQuery.maybeOf(context)?.disableAnimations == true
          ? Duration.zero
          : const Duration(milliseconds: 280);

  void _report(
    DeveloperOperationTrace? trace,
    String message, {
    double? progress,
  }) {
    if (trace != null) {
      trace.log(message, progress: progress);
    } else {
      debugPrint('[PLATE_BILLING_COUNT] $message');
    }
  }

  Future<DeveloperOperationTrace?> _startTrace(
    String title,
    String initialMessage,
  ) async {
    if (!DevAuth.devModeEnabled.value || !mounted) return null;
    return DeveloperOperationTrace.start(
      context: context,
      title: title,
      initialMessage: initialMessage,
      useCommonUi: false,
      developerModeMessage: '개발자 모드에서 삭제 작업 로그를 기록합니다.',
      showDialogImmediately: true,
    );
  }

  void _markDeleting() {
    setState(() {
      _deleting = true;
      _deleteProgress = 0;
    });
  }

  void _markDeleteProgress(int completed, int total) {
    if (!mounted) return;
    setState(() {
      _deleteProgress = total == 0 ? 1.0 : completed / total;
    });
  }

  Future<void> _reportFailure(
    DeveloperOperationTrace? trace,
    String message,
    Object error,
    StackTrace stackTrace,
  ) async {
    _report(trace, '$message: $error');
    if (trace != null) {
      await trace.fail(message, error: error, stackTrace: stackTrace);
      return;
    }
    if (mounted) {
      await StatusDialog.showFailure(
        context,
        title: '청구 카운트 삭제 실패',
        description: message,
      );
    }
  }

  Widget _switchContent(Widget child) {
    return AnimatedSwitcher(
      duration: _motionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (widget, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(animation),
          child: widget,
        ),
      ),
      child: child,
    );
  }

  @override
  void initState() {
    super.initState();
    final now = PlateBillingCountService.nowInKst();
    _selectedMonth = DateTime(now.year, now.month);
    _rowsFuture = _repository.fetchByMonth(_monthKey);
  }

  String get _monthKey {
    final month = _selectedMonth.month.toString().padLeft(2, '0');
    return '${_selectedMonth.year}-$month';
  }

  String _formatUpdatedAt(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }

  void _moveMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
      _reloadKey++;
      _rowsFuture = _repository.fetchByMonth(_monthKey);
    });
  }

  void _resetToCurrentMonth() {
    final now = PlateBillingCountService.nowInKst();
    setState(() {
      _selectedMonth = DateTime(now.year, now.month);
      _reloadKey++;
      _rowsFuture = _repository.fetchByMonth(_monthKey);
    });
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _reloadKey++;
      _rowsFuture = _repository.fetchByMonth(_monthKey);
    });
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deleteRow(PlateBillingCountModel row) async {
    final ok = await _confirm(
      title: '청구 카운트 삭제',
      message: '${row.month} ${row.company} ${row.area} 문서를 삭제할까요?',
    );
    if (!ok || !mounted) return;
    _markDeleting();
    DeveloperOperationTrace? trace;
    try {
      trace = await _startTrace(
        '청구 카운트 문서 삭제',
        '${row.month} 청구 카운트 문서 삭제를 시작합니다.',
      );
      _report(
        trace,
        'deleteDocument start month=${row.month} id=${row.id}',
        progress: 0.15,
      );
      await _repository.deleteDocument(row.id);
      _markDeleteProgress(1, 1);
      _report(
        trace,
        'deleteDocument committed month=${row.month} id=${row.id}',
        progress: 0.85,
      );
      if (mounted) await _reload();
      if (trace != null) {
        await trace.succeed('청구 카운트 문서 삭제를 완료했습니다.');
      } else {
        _report(null, 'deleteDocument success count=1');
      }
    } catch (error, stackTrace) {
      await _reportFailure(
        trace,
        '청구 카운트 문서를 삭제하지 못했습니다.',
        error,
        stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _deleteMonth() async {
    final month = _monthKey;
    final ok = await _confirm(
      title: '월별 청구 카운트 삭제',
      message: '$month 월의 청구 카운트 문서를 모두 삭제할까요?',
    );
    if (!ok || !mounted) return;
    _markDeleting();
    DeveloperOperationTrace? trace;
    try {
      trace = await _startTrace(
        '월별 청구 카운트 삭제',
        '$month 월의 청구 카운트 삭제를 시작합니다.',
      );
      _report(trace, 'deleteMonth start month=$month', progress: 0.1);
      final deleted = await _repository.deleteMonth(
        month,
        onProgress: (completed, total) {
          _markDeleteProgress(completed, total);
          _report(
            trace,
            'deleteMonth batchCommitted month=$month '
            'completed=$completed total=$total',
            progress: total == 0 ? 0.9 : 0.1 + 0.8 * completed / total,
          );
        },
      );
      _markDeleteProgress(1, 1);
      _report(
        trace,
        'deleteMonth success month=$month deleted=$deleted',
        progress: 0.95,
      );
      if (mounted) await _reload();
      if (trace != null) {
        await trace.succeed('$month 월 청구 카운트 $deleted건을 삭제했습니다.');
      } else {
        _report(null, 'deleteMonth completed month=$month count=$deleted');
      }
    } catch (error, stackTrace) {
      await _reportFailure(
        trace,
        '$month 월 청구 카운트 삭제에 실패했습니다.',
        error,
        stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '청구',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          '회사별 지역별 신규 입차 세션 집계',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: DevAuth.devModeEnabled,
                    builder: (context, enabled, _) => enabled
                        ? IconButton(
                            tooltip: 'Firebase 작업 상태',
                            onPressed: () =>
                                FirebaseActivityStatusDialog.show(context),
                            icon: const Icon(Icons.terminal_rounded),
                          )
                        : const SizedBox.shrink(),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: '이전 달',
                    onPressed: _deleting ? null : () => _moveMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: AnimatedSwitcher(
                      duration: _motionDuration,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.94, end: 1)
                              .animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        _monthKey,
                        key: ValueKey<String>(_monthKey),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '다음 달',
                    onPressed: _deleting ? null : () => _moveMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  OutlinedButton.icon(
                    onPressed: _deleting ? null : _resetToCurrentMonth,
                    icon: const Icon(Icons.today_rounded),
                    label: const Text('이번 달'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _deleting ? null : _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('새로고침'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _deleting ? null : _deleteMonth,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('월 전체 삭제'),
                  ),
                ],
              ),
              AnimatedSize(
                duration: _motionDuration,
                curve: Curves.easeOutCubic,
                child: _deleting
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  begin: 0,
                                  end: _deleteProgress,
                                ),
                                duration: _motionDuration,
                                curve: Curves.easeOutCubic,
                                builder: (context, value, _) =>
                                    LinearProgressIndicator(
                                  value: value,
                                  minHeight: 6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: _motionDuration,
                  child: FutureBuilder<List<PlateBillingCountModel>>(
                    key: ValueKey('$_monthKey-$_reloadKey'),
                    future: _rowsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _switchContent(
                          const Center(
                            key: ValueKey<String>('billing_loading'),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return _switchContent(Center(
                          key: const ValueKey<String>('billing_error'),
                          child: Text(
                            '청구 카운트를 불러오지 못했습니다.\n${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                        ));
                      }
                      final rows = snapshot.data ?? const <PlateBillingCountModel>[];
                      if (rows.isEmpty) {
                        return _switchContent(Center(
                          key: const ValueKey<String>('billing_empty'),
                          child: Text(
                            '$_monthKey 월에 집계된 신규 입차 세션이 없습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ));
                      }
                      final total = rows.fold<int>(0, (sum, row) => sum + row.count);
                      return _switchContent(Column(
                        key: const ValueKey<String>('billing_rows'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '총 $total건 · ${rows.length}개 집계 문서',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Scrollbar(
                              child: SingleChildScrollView(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('회사')),
                                      DataColumn(label: Text('지역')),
                                      DataColumn(label: Text('청구 건수'), numeric: true),
                                      DataColumn(label: Text('마지막 차량')),
                                      DataColumn(label: Text('마지막 등록자')),
                                      DataColumn(label: Text('집계일시')),
                                      DataColumn(label: Text('수정일시')),
                                      DataColumn(label: Text('관리')),
                                    ],
                                    rows: rows
                                        .map(
                                          (row) => DataRow(
                                            cells: [
                                              DataCell(Text(row.company)),
                                              DataCell(Text(row.area)),
                                              DataCell(Text('${row.count}')),
                                              DataCell(Text(row.lastPlateNumber ?? '-')),
                                              DataCell(Text(row.lastUserName ?? '-')),
                                              DataCell(Text(_formatUpdatedAt(row.lastCountedAt))),
                                              DataCell(Text(_formatUpdatedAt(row.updatedAt))),
                                              DataCell(
                                                IconButton(
                                                  tooltip: '문서 삭제',
                                                  onPressed: _deleting ? null : () => _deleteRow(row),
                                                  icon: const Icon(Icons.delete_outline_rounded),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                        .toList(growable: false),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
