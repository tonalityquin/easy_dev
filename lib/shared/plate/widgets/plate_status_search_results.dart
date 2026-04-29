import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/models/plate_status_search_result.dart';

class PlateStatusSearchResults extends StatelessWidget {
  final List<PlateStatusSearchResult> results;

  const PlateStatusSearchResults({
    super.key,
    required this.results,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '검색 결과',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${results.length}건',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = results[index];
            return _PlateStatusResultCard(item: item);
          },
        ),
      ],
    );
  }
}

class _PlateStatusResultCard extends StatelessWidget {
  final PlateStatusSearchResult item;

  const _PlateStatusResultCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plateNumber = item.stringValue('plateNumber') ?? item.docId;
    final monthKey = item.stringValue('monthKey') ?? '-';
    final customStatus = item.stringValue('customStatus');
    final statusList = item.data['statusList'];
    final hasStatusList = statusList is List && statusList.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.assignment_outlined,
                    color: cs.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plateNumber,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _ChipText(text: 'plate_status', icon: Icons.storage),
                          _ChipText(text: monthKey, icon: Icons.calendar_month),
                          if (customStatus != null)
                            _ChipText(text: '메모 있음', icon: Icons.edit_note),
                          if (hasStatusList)
                            _ChipText(text: '상태 ${statusList.length}개', icon: Icons.sell_outlined),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldRow(label: 'docId', value: item.docId),
                  const SizedBox(height: 8),
                  _FieldRow(label: 'path', value: item.path),
                  ...item.orderedEntries().map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _FieldRow(
                            label: entry.key,
                            value: _formatValue(entry.value),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return '-';

    try {
      final dynamic dynamicValue = value;
      final converted = dynamicValue.toDate();
      if (converted is DateTime) {
        return DateFormat('yyyy-MM-dd HH:mm:ss').format(converted);
      }
    } catch (_) {}

    if (value is DateTime) {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(value);
    }

    if (value is List) {
      if (value.isEmpty) return '[]';
      return value.map(_formatValue).join(', ');
    }

    if (value is Map) {
      if (value.isEmpty) return '{}';
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return entries.map((e) => '${e.key}: ${_formatValue(e.value)}').join(', ');
    }

    return value.toString();
  }
}

class _ChipText extends StatelessWidget {
  final String text;
  final IconData icon;

  const _ChipText({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: cs.onSecondaryContainer,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;

  const _FieldRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}
