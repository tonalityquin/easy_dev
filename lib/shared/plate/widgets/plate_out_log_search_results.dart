import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../secondary/widgets/ops_console_widgets.dart';
import '../domain/models/plate_out_log_search_result.dart';

class PlateOutLogSearchResults extends StatefulWidget {
  const PlateOutLogSearchResults({
    super.key,
    required this.results,
    required this.trace,
  });

  final List<PlateOutLogSearchResult> results;
  final DeveloperOperationTrace trace;

  @override
  State<PlateOutLogSearchResults> createState() =>
      _PlateOutLogSearchResultsState();
}

class _PlateOutLogSearchResultsState extends State<PlateOutLogSearchResults> {
  final Map<String, bool> _newestFirstByVehicle = <String, bool>{};
  String? _expandedVehicleKey;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final groups = _buildVehicleGroups(widget.results);

    return OpsDockListSurface(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: groups.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          color: tokens.borderSubtle,
        ),
        itemBuilder: (context, index) {
          final group = groups[index];
          final expanded = _expandedVehicleKey == group.key;
          final newestFirst = _newestFirstByVehicle[group.key] ?? true;
          final sortedLogs = List<_PlateOutLogEntry>.from(group.logs)
            ..sort((a, b) => _compareDates(a, b, newestFirst));
          return _VehicleOutLogManagementRow(
            group: group,
            logs: sortedLogs,
            expanded: expanded,
            newestFirst: newestFirst,
            onTap: () => _toggleExpanded(group.key),
            onSortChanged: (value) => _setSort(group.key, value),
          );
        },
      ),
    );
  }

  int _compareDates(
    _PlateOutLogEntry a,
    _PlateOutLogEntry b,
    bool newestFirst,
  ) {
    final ad = a.departureCompletedAt;
    final bd = b.departureCompletedAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return newestFirst ? 1 : -1;
    if (bd == null) return newestFirst ? -1 : 1;
    return newestFirst ? bd.compareTo(ad) : ad.compareTo(bd);
  }

  void _toggleExpanded(String key) {
    HapticFeedback.selectionClick();
    final next = _expandedVehicleKey == key ? null : key;
    setState(() => _expandedVehicleKey = next);
    final message =
        'plate_out_log_vehicle_toggle key=$key expanded=${next == key} presentation=ops_management_row';
    widget.trace.log(message);
    debugPrint('[PlateOutLogManagement] $message');
  }

  void _setSort(String key, bool newestFirst) {
    HapticFeedback.selectionClick();
    setState(() => _newestFirstByVehicle[key] = newestFirst);
    final message =
        'plate_out_log_sort_changed key=$key newestFirst=$newestFirst presentation=ops_management_row';
    widget.trace.log(message);
    debugPrint('[PlateOutLogManagement] $message');
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
      final key = plateDocId.isNotEmpty ? plateDocId : '$plateNumber|$area';

      final group = byVehicle.putIfAbsent(
        key,
        () => _VehicleOutLogGroup(
          key: key,
          plateNumber: plateNumber,
          area: area,
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

    final sectorEnabled = _boolValue(log, const ['sectorEnabled']) ??
        _boolValue(data, const ['sectorEnabled']) ??
        (log.containsKey('sectorId') ||
            log.containsKey('sectorName') ||
            data.containsKey('lastSectorId') ||
            data.containsKey('lastSectorName'));
    final sectorId = _stringValue(log, const ['sectorId']) ??
        _stringValue(data, const ['lastSectorId', 'sectorId']);
    final sectorName = _stringValue(log, const ['sectorName']) ??
        _stringValue(data, const ['lastSectorName', 'sectorName']);
    final sectorAssigned = _boolValue(log, const ['sectorAssigned']) ??
        _boolValue(data, const ['lastSectorAssigned']) ??
        ((sectorId?.isNotEmpty ?? false) && (sectorName?.isNotEmpty ?? false));
    final sectorDataValid = _boolValue(log, const ['sectorDataValid']) ??
        _boolValue(data, const ['lastSectorDataValid']) ??
        true;

    return _PlateOutLogEntry(
      departureCompletedAt: completedAt,
      departureCompletedDateText:
          _stringValue(log, const ['departureCompletedDate']),
      departureCompletedTimeText:
          _stringValue(log, const ['departureCompletedTime']),
      paymentMethod: paymentMethod,
      lockedFeeAmount: lockedFeeAmount,
      reason: reason,
      customStatus: customStatus,
      sectorEnabled: sectorEnabled,
      sectorId: sectorId,
      sectorName: sectorName,
      sectorAssigned: sectorAssigned,
      sectorDataValid: sectorDataValid,
    );
  }

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

  bool? _boolValue(Map<dynamic, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
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
    final index = docId.indexOf('_');
    if (index <= 0) return docId;
    return docId.substring(0, index);
  }
}

class _VehicleOutLogGroup {
  _VehicleOutLogGroup({
    required this.key,
    required this.plateNumber,
    required this.area,
    required this.logs,
  });

  final String key;
  final String plateNumber;
  final String area;
  final List<_PlateOutLogEntry> logs;
}

class _PlateOutLogEntry {
  const _PlateOutLogEntry({
    required this.departureCompletedAt,
    required this.departureCompletedDateText,
    required this.departureCompletedTimeText,
    required this.paymentMethod,
    required this.lockedFeeAmount,
    required this.reason,
    required this.customStatus,
    required this.sectorEnabled,
    required this.sectorId,
    required this.sectorName,
    required this.sectorAssigned,
    required this.sectorDataValid,
  });

  final DateTime? departureCompletedAt;
  final String? departureCompletedDateText;
  final String? departureCompletedTimeText;
  final String? paymentMethod;
  final int? lockedFeeAmount;
  final String? reason;
  final String? customStatus;
  final bool sectorEnabled;
  final String? sectorId;
  final String? sectorName;
  final bool sectorAssigned;
  final bool sectorDataValid;
}

class _VehicleOutLogManagementRow extends StatelessWidget {
  const _VehicleOutLogManagementRow({
    required this.group,
    required this.logs,
    required this.expanded,
    required this.newestFirst,
    required this.onTap,
    required this.onSortChanged,
  });

  final _VehicleOutLogGroup group;
  final List<_PlateOutLogEntry> logs;
  final bool expanded;
  final bool newestFirst;
  final VoidCallback onTap;
  final ValueChanged<bool> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final latest = logs.isEmpty ? null : logs.first;
    final latestText = latest == null ? '출차 시각 없음' : _entryTime(latest);

    return Semantics(
      button: true,
      selected: expanded,
      label: '${group.plateNumber}, 출차 로그 ${logs.length}건, $latestText',
      child: OpsDockSelectableRowSurface(
        selected: expanded,
        selectionColor: tokens.accent,
        selectedContainer: tokens.accentContainer,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.info,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    group.plateNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.1,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '로그 ${logs.length}건',
                  style: textTheme.labelSmall?.copyWith(
                    color: tokens.info,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 5),
                AnimatedRotation(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  turns: expanded ? .25 : 0,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: expanded ? tokens.accent : tokens.iconSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${group.area} · $latestText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 9),
              Container(height: 1, color: tokens.borderSubtle),
              const SizedBox(height: 7),
              _LogSortControls(
                newestFirst: newestFirst,
                reduceMotion: reduceMotion,
                onChanged: onSortChanged,
              ),
              const SizedBox(height: 6),
              for (int index = 0; index < logs.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 13,
                    thickness: 1,
                    color: tokens.borderSubtle,
                  ),
                _OutLogManagementEntry(entry: logs[index]),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _entryTime(_PlateOutLogEntry entry) {
    final date = entry.departureCompletedAt;
    if (date != null) return DateFormat('MM.dd HH:mm').format(date.toLocal());
    final rawDate = entry.departureCompletedDateText?.trim();
    final rawTime = entry.departureCompletedTimeText?.trim();
    if (rawDate?.isNotEmpty == true && rawTime?.isNotEmpty == true) {
      return '$rawDate $rawTime';
    }
    if (rawDate?.isNotEmpty == true) return rawDate!;
    if (rawTime?.isNotEmpty == true) return rawTime!;
    return '출차 시각 없음';
  }
}

class _LogSortControls extends StatelessWidget {
  const _LogSortControls({
    required this.newestFirst,
    required this.reduceMotion,
    required this.onChanged,
  });

  final bool newestFirst;
  final bool reduceMotion;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LogSortAction(
            selected: newestFirst,
            label: '최신 순',
            icon: Icons.south_rounded,
            reduceMotion: reduceMotion,
            onTap: () => onChanged(true),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: _LogSortAction(
            selected: !newestFirst,
            label: '오래된 순',
            icon: Icons.north_rounded,
            reduceMotion: reduceMotion,
            onTap: () => onChanged(false),
          ),
        ),
      ],
    );
  }
}

class _LogSortAction extends StatefulWidget {
  const _LogSortAction({
    required this.selected,
    required this.label,
    required this.icon,
    required this.reduceMotion,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  State<_LogSortAction> createState() => _LogSortActionState();
}

class _LogSortActionState extends State<_LogSortAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final foreground =
        widget.selected ? tokens.accent : tokens.textSecondary;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: AnimatedScale(
        duration: widget.reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        scale: _pressed ? .97 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() => _pressed = value);
            },
            child: AnimatedContainer(
              duration: widget.reduceMotion
                  ? Duration.zero
                  : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: widget.selected
                    ? tokens.accentContainer.withOpacity(.58)
                    : tokens.surfaceOverlay.withOpacity(.36),
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(
                  color: widget.selected
                      ? tokens.accent.withOpacity(.32)
                      : tokens.borderSubtle,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 14, color: foreground),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutLogManagementEntry extends StatelessWidget {
  const _OutLogManagementEntry({required this.entry});

  final _PlateOutLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final fee = entry.lockedFeeAmount == null
        ? '정산 금액 -'
        : '정산 ₩${NumberFormat('#,###', 'ko_KR').format(entry.lockedFeeAmount)}';
    final payment = _safeText(entry.paymentMethod, fallback: '결제 수단 없음');
    final sector = _sectorText(entry);
    final notes = <String>[
      if ((entry.reason ?? '').trim().isNotEmpty) (entry.reason ?? '').trim(),
      if ((entry.customStatus ?? '').trim().isNotEmpty)
        (entry.customStatus ?? '').trim(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _dateTimeText(entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              fee,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.success,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '$sector · $payment',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(
            color: entry.sectorDataValid
                ? tokens.textSecondary
                : tokens.danger,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            notes.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }

  String _dateTimeText(_PlateOutLogEntry entry) {
    final date = entry.departureCompletedAt;
    if (date != null) {
      return DateFormat('yyyy.MM.dd HH:mm:ss').format(date.toLocal());
    }
    final rawDate = entry.departureCompletedDateText?.trim();
    final rawTime = entry.departureCompletedTimeText?.trim();
    final parts = <String>[
      if (rawDate?.isNotEmpty == true) rawDate!,
      if (rawTime?.isNotEmpty == true) rawTime!,
    ];
    return parts.isEmpty ? '출차 시각 없음' : parts.join(' ');
  }

  String _sectorText(_PlateOutLogEntry entry) {
    if (!entry.sectorEnabled) return '방문 구역 미사용';
    if (!entry.sectorDataValid) return '방문 구역 데이터 확인 필요';
    if (!entry.sectorAssigned) return '방문 구역 미지정';
    final name = entry.sectorName?.trim();
    if (name?.isNotEmpty == true) return name!;
    final id = entry.sectorId?.trim();
    if (id?.isNotEmpty == true) return id!;
    return '방문 구역 미지정';
  }

  String _safeText(String? value, {required String fallback}) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return fallback;
    return text;
  }
}
