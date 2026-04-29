import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/models/plate_out_log_search_result.dart';

class PlateOutLogSearchResults extends StatefulWidget {
  final List<PlateOutLogSearchResult> results;

  const PlateOutLogSearchResults({
    super.key,
    required this.results,
  });

  @override
  State<PlateOutLogSearchResults> createState() =>
      _PlateOutLogSearchResultsState();
}

class _PlateOutLogSearchResultsState extends State<PlateOutLogSearchResults> {
  final Map<String, bool> _newestFirstByVehicle = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = _buildVehicleGroups(widget.results);
    final totalLogs = groups.fold<int>(0, (sum, group) => sum + group.logs.length);

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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.85),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '차량 ${groups.length}대 · 로그 $totalLogs건',
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: groups.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final group = groups[index];
            final newestFirst = _newestFirstByVehicle[group.key] ?? true;
            final sortedLogs = List<_PlateOutLogEntry>.from(group.logs)
              ..sort((a, b) {
                final ad = a.departureCompletedAt;
                final bd = b.departureCompletedAt;
                if (ad == null && bd == null) return 0;
                if (ad == null) return newestFirst ? 1 : -1;
                if (bd == null) return newestFirst ? -1 : 1;
                return newestFirst ? bd.compareTo(ad) : ad.compareTo(bd);
              });

            return _VehicleOutLogCard(
              group: group,
              logs: sortedLogs,
              newestFirst: newestFirst,
              onSortChanged: (value) {
                setState(() {
                  _newestFirstByVehicle[group.key] = value;
                });
              },
            );
          },
        ),
      ],
    );
  }

  List<_VehicleOutLogGroup> _buildVehicleGroups(
    List<PlateOutLogSearchResult> results,
  ) {
    final byVehicle = <String, _VehicleOutLogGroup>{};

    for (final item in results) {
      final data = item.data;
      final plateDocId = _stringValue(data, const ['plateDocId']) ?? item.docId;
      final plateNumber =
          _stringValue(data, const ['plateNumber', 'plate_number']) ??
              _plateNumberFromDocId(plateDocId);
      final area = _stringValue(data, const ['area']) ?? '-';
      final fourDigit =
          _stringValue(data, const ['plate_four_digit']) ?? _lastFourDigits(plateNumber);
      final key = plateDocId.isNotEmpty ? plateDocId : '$plateNumber|$area';

      final group = byVehicle.putIfAbsent(
        key,
        () => _VehicleOutLogGroup(
          key: key,
          plateDocId: plateDocId,
          plateNumber: plateNumber,
          area: area,
          fourDigit: fourDigit,
          logs: <_PlateOutLogEntry>[],
        ),
      );

      group.logs.addAll(_extractLogs(item));
    }

    final groups = byVehicle.values.toList()
      ..sort((a, b) => a.plateNumber.compareTo(b.plateNumber));
    return groups;
  }

  List<_PlateOutLogEntry> _extractLogs(PlateOutLogSearchResult item) {
    final data = item.data;
    final rawLogs = data['logs'];
    final entries = <_PlateOutLogEntry>[];

    if (rawLogs is List) {
      for (final raw in rawLogs) {
        if (raw is Map) {
          entries.add(_entryFromMap(item, Map<String, dynamic>.from(raw)));
        }
      }
    }

    if (entries.isEmpty) {
      entries.add(_entryFromMap(item, const <String, dynamic>{}));
    }

    return entries;
  }

  _PlateOutLogEntry _entryFromMap(
    PlateOutLogSearchResult item,
    Map<String, dynamic> log,
  ) {
    final data = item.data;
    final completedAt = _readDate(log['departureCompletedAt']) ??
        _readDateFromText(
          _stringValue(log, const ['departureCompletedDate']),
          _stringValue(log, const ['departureCompletedTime']),
        ) ??
        _readDate(data['lastDepartureCompletedAt']) ??
        _readDate(data['departureCompletedAt']) ??
        _readDate(data['updatedAt']);

    final paymentMethod = _stringValue(log, const ['paymentMethod']) ??
        _stringValue(data, const ['lastPaymentMethod', 'paymentMethod']);

    final lockedFeeAmount =
        _intValue(log, const ['lockedFeeAmount', 'lockedFee']) ??
            _intValue(data, const ['lastLockedFeeAmount', 'lockedFeeAmount']);

    final reason = _stringValue(log, const ['reason']) ??
        _stringValue(data, const ['lastReason', 'reason']);

    final customStatus = _stringValue(log, const ['customStatus']) ??
        _stringValue(data, const ['lastCustomStatus', 'customStatus']);

    final logKey = _stringValue(log, const ['logKey']) ??
        '${item.path}|${_safeToken(completedAt)}|${paymentMethod ?? ''}|${lockedFeeAmount ?? ''}';

    return _PlateOutLogEntry(
      logKey: logKey,
      departureCompletedAt: completedAt,
      departureCompletedDateText:
          _stringValue(log, const ['departureCompletedDate']),
      departureCompletedTimeText:
          _stringValue(log, const ['departureCompletedTime']),
      paymentMethod: paymentMethod,
      lockedFeeAmount: lockedFeeAmount,
      reason: reason,
      customStatus: customStatus,
    );
  }

  String _safeToken(DateTime? dateTime) => dateTime?.toIso8601String() ?? 'unknown';

  String? _stringValue(Map<dynamic, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  int? _intValue(Map<dynamic, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.replaceAll(',', '').trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  DateTime? _readDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    if (value is String) return DateTime.tryParse(value);

    try {
      final dynamic dynamicValue = value;
      final converted = dynamicValue.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}

    return null;
  }

  DateTime? _readDateFromText(String? dateText, String? timeText) {
    final date = dateText?.trim();
    if (date == null || date.isEmpty) return null;
    final time = timeText?.trim();
    return DateTime.tryParse(
      time == null || time.isEmpty ? date : '$date $time',
    );
  }

  String _plateNumberFromDocId(String docId) {
    final idx = docId.indexOf('_');
    if (idx <= 0) return docId;
    return docId.substring(0, idx);
  }

  String _lastFourDigits(String plateNumber) {
    final key = plateNumber.replaceAll('-', '').replaceAll(' ', '').trim();
    if (key.length <= 4) return key;
    return key.substring(key.length - 4);
  }
}

class _VehicleOutLogGroup {
  final String key;
  final String plateDocId;
  final String plateNumber;
  final String area;
  final String fourDigit;
  final List<_PlateOutLogEntry> logs;

  _VehicleOutLogGroup({
    required this.key,
    required this.plateDocId,
    required this.plateNumber,
    required this.area,
    required this.fourDigit,
    required this.logs,
  });
}

class _PlateOutLogEntry {
  final String logKey;
  final DateTime? departureCompletedAt;
  final String? departureCompletedDateText;
  final String? departureCompletedTimeText;
  final String? paymentMethod;
  final int? lockedFeeAmount;
  final String? reason;
  final String? customStatus;

  const _PlateOutLogEntry({
    required this.logKey,
    required this.departureCompletedAt,
    required this.departureCompletedDateText,
    required this.departureCompletedTimeText,
    required this.paymentMethod,
    required this.lockedFeeAmount,
    required this.reason,
    required this.customStatus,
  });
}

class _VehicleOutLogCard extends StatelessWidget {
  final _VehicleOutLogGroup group;
  final List<_PlateOutLogEntry> logs;
  final bool newestFirst;
  final ValueChanged<bool> onSortChanged;

  const _VehicleOutLogCard({
    required this.group,
    required this.logs,
    required this.newestFirst,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 10),
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
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: cs.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.plateNumber,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SortSegment(
              newestFirst: newestFirst,
              onChanged: onSortChanged,
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _OutLogEntryCard(entry: logs[index]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SortSegment extends StatelessWidget {
  final bool newestFirst;
  final ValueChanged<bool> onChanged;

  const _SortSegment({
    required this.newestFirst,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SortOption(
              selected: newestFirst,
              label: '최신 순',
              icon: Icons.south_rounded,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _SortOption(
              selected: !newestFirst,
              label: '오래된 순',
              icon: Icons.north_rounded,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SortOption({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutLogEntryCard extends StatelessWidget {
  final _PlateOutLogEntry entry;

  const _OutLogEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currency = NumberFormat('#,###');
    final dateText = _dateTitle(entry);
    final timeText = _timeText(entry);
    final feeText = entry.lockedFeeAmount == null
        ? '-'
        : '${currency.format(entry.lockedFeeAmount)}원';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withOpacity(0.86),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.event_available_rounded,
                  color: cs.onTertiaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateText,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$timeText · 출차 정산 기록',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.62)),
            ),
            child: Row(
              children: [
                _PaymentMethodChip(text: _safeText(entry.paymentMethod)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    feeText,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _DetailCard(
            label: 'reason',
            value: _safeText(entry.reason),
            icon: Icons.notes_rounded,
          ),
          const SizedBox(height: 8),
          _DetailCard(
            label: '상태 메모',
            value: _safeText(entry.customStatus),
            icon: Icons.sticky_note_2_outlined,
          ),
        ],
      ),
    );
  }

  String _dateTitle(_PlateOutLogEntry entry) {
    final date = entry.departureCompletedAt;
    if (date != null) {
      return '${date.year}년 ${date.month}월 ${date.day}일';
    }

    final raw = entry.departureCompletedDateText?.trim();
    if (raw == null || raw.isEmpty) return '날짜 없음';

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return '${parsed.year}년 ${parsed.month}월 ${parsed.day}일';
    }

    return raw;
  }

  String _timeText(_PlateOutLogEntry entry) {
    final date = entry.departureCompletedAt;
    if (date != null) {
      return DateFormat('HH:mm:ss').format(date);
    }

    final raw = entry.departureCompletedTimeText?.trim();
    if (raw == null || raw.isEmpty) return '시간 없음';
    return raw;
  }

  String _safeText(String? text) {
    final value = text?.trim();
    if (value == null || value.isEmpty) return '-';
    return value;
  }
}

class _PaymentMethodChip extends StatelessWidget {
  final String text;

  const _PaymentMethodChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(0.86),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.credit_card_rounded,
            size: 14,
            color: cs.onSecondaryContainer,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: cs.onSecondaryContainer,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: cs.onSurfaceVariant),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    height: 1.28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

