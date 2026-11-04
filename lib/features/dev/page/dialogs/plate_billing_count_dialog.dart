import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  int _reloadKey = 0;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final now = PlateBillingCountService.nowInKst();
    _selectedMonth = DateTime(now.year, now.month);
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
    });
  }

  void _resetToCurrentMonth() {
    final now = PlateBillingCountService.nowInKst();
    setState(() {
      _selectedMonth = DateTime(now.year, now.month);
      _reloadKey++;
    });
  }

  Future<void> _reload() async {
    setState(() => _reloadKey++);
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
    setState(() => _deleting = true);
    try {
      await _repository.deleteDocument(row.id);
      await _reload();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _deleteMonth() async {
    final ok = await _confirm(
      title: '월별 청구 카운트 삭제',
      message: '$_monthKey 월의 청구 카운트 문서를 모두 삭제할까요?',
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _repository.deleteMonth(_monthKey);
      await _reload();
    } finally {
      if (mounted) setState(() => _deleting = false);
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
                    child: Text(
                      _monthKey,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
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
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<PlateBillingCountModel>>(
                  key: ValueKey('$_monthKey-$_reloadKey'),
                  future: _repository.fetchByMonth(_monthKey),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          '청구 카운트를 불러오지 못했습니다.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    final rows = snapshot.data ?? const <PlateBillingCountModel>[];
                    if (rows.isEmpty) {
                      return Center(
                        child: Text(
                          '$_monthKey 월에 집계된 신규 입차 세션이 없습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      );
                    }
                    final total = rows.fold<int>(0, (sum, row) => sum + row.count);
                    return Column(
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
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
