import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/storage/v1.dart' as gcs;
import 'package:http/http.dart' as http;

import '../../../app/auth/google_auth_v7.dart';
import '../../../app/config/auth_config.dart';
import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../secondary/widgets/ops_console_widgets.dart';

class DepartureCompletedHistoryWorkspace extends StatefulWidget {
  const DepartureCompletedHistoryWorkspace({
    super.key,
    required this.division,
    required this.area,
    required this.onOpenImage,
    required this.onDebug,
  });

  final String division;
  final String area;
  final Future<void> Function(BuildContext context, String plateNumber)
      onOpenImage;
  final ValueChanged<String> onDebug;

  @override
  State<DepartureCompletedHistoryWorkspace> createState() =>
      _DepartureCompletedHistoryWorkspaceState();
}

class _DepartureCompletedHistoryWorkspaceState
    extends State<DepartureCompletedHistoryWorkspace> {
  final TextEditingController _queryController = TextEditingController();

  DateTimeRange? _selectedRange;
  DateTimeRange? _executedRange;
  List<_HistoryRecord> _records = const <_HistoryRecord>[];
  String _query = '';
  String? _executedQuery;
  String? _selectedId;
  String? _error;
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _log(
        'initialized autoLoad=false networkRead=0 rangeSelected=false queryReady=false',
      );
    });
  }

  @override
  void didUpdateWidget(covariant DepartureCompletedHistoryWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.division.trim() != widget.division.trim() ||
        oldWidget.area.trim() != widget.area.trim()) {
      _queryController.clear();
      setState(() {
        _selectedRange = null;
        _executedRange = null;
        _records = const <_HistoryRecord>[];
        _query = '';
        _executedQuery = null;
        _selectedId = null;
        _error = null;
        _loading = false;
        _searched = false;
      });
      _log(
        'context_changed division=${widget.division.trim()} area=${widget.area.trim()} reset=true autoLoad=false networkRead=0',
      );
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _log(String message) {
    widget.onDebug('history_$message');
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _ymd(DateTime date) =>
      '${date.year}-${_two(date.month)}-${_two(date.day)}';

  String _monthKey(DateTime date) => '${date.year}${_two(date.month)}';

  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    if (value is int) {
      final millis = value > 100000000000 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  num? _parseNumber(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString().trim() ?? '');
  }

  String? _stringValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '—';
    return '${_two(value.month)}.${_two(value.day)} ${_two(value.hour)}:${_two(value.minute)}';
  }

  String _formatWon(num? amount) {
    if (amount == null) return '—';
    final source = amount.round().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      if (index > 0 && (source.length - index) % 3 == 0) buffer.write(',');
      buffer.write(source[index]);
    }
    return '${buffer.toString()}원';
  }

  String _tail4(String plateNumber, String docId, String? storedTail) {
    final direct = storedTail?.trim() ?? '';
    if (RegExp(r'^\d{4}$').hasMatch(direct)) return direct;
    final digits = (plateNumber.isNotEmpty ? plateNumber : docId)
        .replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return '';
    return digits.substring(digits.length - 4);
  }

  List<String> _monthKeys(DateTime start, DateTime end) {
    final first = DateTime(start.year, start.month);
    final last = DateTime(end.year, end.month);
    final result = <String>[];
    var cursor = first;
    while (!cursor.isAfter(last)) {
      result.add(_monthKey(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return result;
  }

  Future<List<String>> _listObjects(String prefix) async {
    final client = await GoogleAuthV7.authedClient(
      [gcs.StorageApi.devstorageReadOnlyScope],
    );
    try {
      final api = gcs.StorageApi(client);
      final result = <String>[];
      String? pageToken;
      do {
        final response = await api.objects.list(
          AuthConfig.gcsBucketName,
          prefix: prefix,
          pageToken: pageToken,
        );
        for (final item in response.items ?? const <gcs.Object>[]) {
          final name = item.name?.trim() ?? '';
          if (name.isNotEmpty) result.add(name);
        }
        pageToken = response.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);
      return result;
    } finally {
      client.close();
    }
  }

  Future<List<Map<String, String>>> _loadCsv(String objectName) async {
    final uri = Uri.parse(
      'https://storage.googleapis.com/${AuthConfig.gcsBucketName}/$objectName',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw StateError('GCS GET ${response.statusCode}');
    }
    return _decodeCsv(utf8.decode(response.bodyBytes));
  }

  List<Map<String, String>> _decodeCsv(String text) {
    final table = _parseCsvTable(text);
    if (table.isEmpty) return const <Map<String, String>>[];
    final headers = table.first
        .map((value) => value.replaceFirst('\ufeff', '').trim())
        .toList();
    final rows = <Map<String, String>>[];
    for (var rowIndex = 1; rowIndex < table.length; rowIndex++) {
      final cells = table[rowIndex];
      if (cells.every((value) => value.trim().isEmpty)) continue;
      final row = <String, String>{};
      for (var column = 0; column < headers.length; column++) {
        final key = headers[column];
        if (key.isEmpty) continue;
        row[key] = column < cells.length ? cells[column] : '';
      }
      rows.add(row);
    }
    return rows;
  }

  List<List<String>> _parseCsvTable(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    var index = 0;
    while (index < text.length) {
      final char = text[index];
      if (quoted) {
        if (char == '"') {
          if (index + 1 < text.length && text[index + 1] == '"') {
            cell.write('"');
            index += 2;
            continue;
          }
          quoted = false;
          index++;
          continue;
        }
        cell.write(char);
        index++;
        continue;
      }
      if (char == '"') {
        quoted = true;
      } else if (char == ',') {
        row.add(cell.toString());
        cell.clear();
      } else if (char == '\n' || char == '\r') {
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
        if (char == '\r' && index + 1 < text.length && text[index + 1] == '\n') {
          index++;
        }
      } else {
        cell.write(char);
      }
      index++;
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  Map<String, dynamic> _meta(Map<String, String> row) {
    final result = <String, dynamic>{};
    row.forEach((key, value) {
      if (key.startsWith('meta.') && value.trim().isNotEmpty) {
        result[key.substring(5)] = value;
      }
    });
    for (final key in <String>['division', 'area', 'docId']) {
      final value = row[key]?.trim() ?? '';
      if (value.isNotEmpty) result[key] = value;
    }
    return result;
  }

  Map<String, dynamic> _logRow(Map<String, String> row) {
    final result = <String, dynamic>{};
    row.forEach((key, value) {
      if (key.startsWith('log.') && value.trim().isNotEmpty) {
        result[key.substring(4)] = value;
      }
    });
    return result;
  }

  String _signature(Map<String, dynamic> log) {
    return <Object?>[
      log['timestamp'],
      log['action'],
      log['performedBy'],
      log['from'],
      log['to'],
      log['lockedFee'],
      log['lockedFeeAmount'],
      log['paymentMethod'],
    ].join('|');
  }

  bool _isValidQuery(String value) =>
      RegExp(r'^\d{4}$').hasMatch(value.trim());

  bool get _queryValid => _isValidQuery(_query);

  bool get _canSearch =>
      !_loading && _selectedRange != null && _queryValid;

  Future<void> _searchHistory() async {
    if (_loading) return;
    final range = _selectedRange;
    final query = _query.trim();
    if (range == null) {
      _log('search_blocked reason=range_missing networkRead=0');
      return;
    }
    if (!_isValidQuery(query)) {
      _log('search_blocked reason=query_invalid networkRead=0 query=$query');
      return;
    }
    final division = widget.division.trim();
    final area = widget.area.trim();
    if (division.isEmpty || area.isEmpty) {
      setState(() {
        _records = const <_HistoryRecord>[];
        _executedRange = DateTimeRange(
          start: range.start,
          end: range.end,
        );
        _executedQuery = query;
        _searched = true;
        _error = '지역 정보를 확인할 수 없습니다';
      });
      _log('search_blocked reason=area_missing networkRead=0');
      return;
    }
    final startDay = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final endDay = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
    );
    final start = startDay.isAfter(endDay) ? endDay : startDay;
    final end = startDay.isAfter(endDay) ? startDay : endDay;
    setState(() {
      _loading = true;
      _records = const <_HistoryRecord>[];
      _selectedId = null;
      _error = null;
      _searched = false;
      _executedRange = null;
      _executedQuery = null;
    });
    _log(
      'search_start division=$division area=$area query=$query start=${_ymd(start)} end=${_ymd(end)} autoLoad=false',
    );
    var listRequests = 0;
    var csvRequests = 0;
    try {
      final names = <String>[];
      final monthKeys = _monthKeys(start, end);
      for (final month in monthKeys) {
        listRequests++;
        names.addAll(await _listObjects('$division/$area/logs/$month/'));
      }
      if (names.isEmpty) {
        listRequests++;
        names.addAll(await _listObjects('$division/$area/logs/'));
      }
      _log(
        'gcs_list_complete requests=$listRequests months=${monthKeys.length} objects=${names.length}',
      );
      final suffixes = <String>{};
      for (
        var day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))
      ) {
        suffixes.add('_ToDoLogs_${_ymd(day)}.csv');
      }
      final objectNames = names
          .where((name) => suffixes.any(name.endsWith))
          .toSet()
          .toList()
        ..sort();
      final map = <String, _MutableHistoryRecord>{};
      for (final objectName in objectNames) {
        final match = RegExp(r'_ToDoLogs_(\d{4}-\d{2}-\d{2})\.csv$')
            .firstMatch(objectName);
        final date = match?.group(1) ?? '';
        csvRequests++;
        for (final row in await _loadCsv(objectName)) {
          final meta = _meta(row);
          final docId = _stringValue(row['docId']) ??
              _stringValue(row['meta.docId']) ??
              _stringValue(meta['docId']);
          if (docId == null) continue;
          final record = map.putIfAbsent(
            '$date|$docId',
            () => _MutableHistoryRecord(date: date, docId: docId),
          );
          record.absorbMeta(meta);
          final log = _logRow(row);
          if (log.isNotEmpty && record.logSignatures.add(_signature(log))) {
            record.logs.add(log);
          }
        }
      }
      _log(
        'gcs_csv_complete requests=$csvRequests candidateFiles=${objectNames.length}',
      );
      final records = map.values
          .map((item) => item.freeze(this))
          .where((item) => item.tail4 == query)
          .toList()
        ..sort((a, b) {
          final byTime = (
            b.lastLogAt ?? DateTime.fromMillisecondsSinceEpoch(0)
          ).compareTo(
            a.lastLogAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
          if (byTime != 0) return byTime;
          return b.date.compareTo(a.date);
        });
      if (!mounted) return;
      setState(() {
        _records = records;
        _executedRange = DateTimeRange(start: start, end: end);
        _executedQuery = query;
        _searched = true;
        _loading = false;
        _error = null;
      });
      _log(
        'search_complete query=$query files=${objectNames.length} records=${records.length} networkRequests=${listRequests + csvRequests}',
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _records = const <_HistoryRecord>[];
        _executedRange = DateTimeRange(start: start, end: end);
        _executedQuery = query;
        _loading = false;
        _searched = true;
        _error = '이력 데이터를 불러오지 못했습니다';
      });
      _log(
        'search_failed query=$query networkRequests=${listRequests + csvRequests} error=$error stack=$stackTrace',
      );
      await StatusDialog.showFailure(
        context,
        title: StatusDialog.pastEntryLogLoadFailed,
      );
    }
  }

  void _setQuery(String value) {
    final next = value.trim();
    if (_query == next) return;
    setState(() {
      _query = next;
      _records = const <_HistoryRecord>[];
      _executedRange = null;
      _executedQuery = null;
      _selectedId = null;
      _error = null;
      _searched = false;
    });
    _log(
      'query_changed value=$next valid=${_isValidQuery(next)} networkRead=0 searchRequired=true',
    );
  }

  void _clearQuery() {
    _queryController.clear();
    _setQuery('');
    _log('query_cleared networkRead=0');
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final fallback = DateTimeRange(
      start: DateTime(now.year, now.month, now.day).subtract(
        const Duration(days: 6),
      ),
      end: DateTime(now.year, now.month, now.day),
    );
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedRange ?? fallback,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    final range = DateTimeRange(
      start: DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      ),
      end: DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      ),
    );
    setState(() {
      _selectedRange = range;
      _executedRange = null;
      _executedQuery = null;
      _records = const <_HistoryRecord>[];
      _selectedId = null;
      _error = null;
      _searched = false;
    });
    _log(
      'range_changed start=${_ymd(range.start)} end=${_ymd(range.end)} networkRead=0 searchRequired=true',
    );
  }

  List<_HistoryRecord> get _visibleRecords => _records;

  _HistoryRecord? get _selectedRecord {
    final id = _selectedId;
    if (id == null) return null;
    for (final record in _visibleRecords) {
      if (record.id == id) return record;
    }
    return null;
  }

  Widget _emptyState(
    BuildContext context,
    String title, {
    VoidCallback? onAction,
    String actionLabel = '다시 불러오기',
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.history_rounded, color: tokens.iconSecondary, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(height: 12),
              CommonButton(
                label: actionLabel,
                onPressed: onAction,
                variant: CommonButtonVariant.secondary,
                haptic: CommonHaptic.selection,
                minHeight: 42,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _statusText {
    final range = _selectedRange;
    if (range == null) return '기간 미선택 · 조회 전';
    final rangeText = '${_ymd(range.start)} ~ ${_ymd(range.end)}';
    if (!_queryValid) return '$rangeText · 번호판 4자리 필요';
    if (_loading) return '$rangeText · ${_query.trim()} · 조회 중';
    if (!_searched) return '$rangeText · ${_query.trim()} · 조회 전';
    final executedRange = _executedRange ?? range;
    final executedQuery = _executedQuery ?? _query.trim();
    final executedRangeText =
        '${_ymd(executedRange.start)} ~ ${_ymd(executedRange.end)}';
    if (_error != null) return '$executedRangeText · $executedQuery · 조회 실패';
    return '$executedRangeText · $executedQuery · ${_records.length}건';
  }

  Widget _body(BuildContext context) {
    if (_selectedRange == null) {
      return const KeyedSubtree(
        key: ValueKey<String>('history-range-required'),
        child: SizedBox.shrink(),
      );
    }
    if (!_queryValid) {
      return KeyedSubtree(
        key: const ValueKey<String>('history-query-required'),
        child: _emptyState(context, '번호판 4자리를 입력해 주세요'),
      );
    }
    if (_error != null) {
      return KeyedSubtree(
        key: const ValueKey<String>('history-error'),
        child: _emptyState(
          context,
          _error!,
          onAction: _searchHistory,
          actionLabel: '다시 검색',
        ),
      );
    }
    if (!_searched) {
      return KeyedSubtree(
        key: const ValueKey<String>('history-search-required'),
        child: _emptyState(
          context,
          '검색을 실행해 주세요',
          onAction: _canSearch ? _searchHistory : null,
          actionLabel: '검색',
        ),
      );
    }
    if (_records.isEmpty) {
      return KeyedSubtree(
        key: ValueKey<String>(
          'history-no-result-${_executedQuery ?? _query.trim()}',
        ),
        child: _emptyState(
          context,
          '검색 결과가 없습니다',
          onAction: _clearQuery,
          actionLabel: '검색 초기화',
        ),
      );
    }
    final tokens = CommonUiTheme.of(context);
    return KeyedSubtree(
      key: ValueKey<String>(
        'history-list-${_records.length}-${_executedQuery ?? _query.trim()}',
      ),
      child: OpsDockListSurface(
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: _records.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            thickness: 1,
            color: tokens.borderSubtle,
          ),
          itemBuilder: (context, index) {
            final record = _records[index];
            final selected = record.id == _selectedId;
            return OpsDockSelectableRowSurface(
              selected: selected,
              selectionColor: tokens.accent,
              selectedContainer: tokens.accentContainer,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedId = selected ? null : record.id);
                _log(
                  'row_${selected ? "deselected" : "selected"} plate=${record.plateNumber}',
                );
              },
              child: _HistoryRow(
                record: record,
                selected: selected,
                formatDateTime: _formatDateTime,
                formatWon: _formatWon,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _rangeRequiredBody(BuildContext context) {
    return _emptyState(
      context,
      '기간을 먼저 선택해 주세요',
      onAction: _loading ? null : _pickRange,
      actionLabel: '기간 선택',
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedRecord;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final body = _selectedRange == null
        ? KeyedSubtree(
            key: const ValueKey<String>('history-range-required'),
            child: _rangeRequiredBody(context),
          )
        : _body(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AnimatedOpacity(
                duration: reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.selection,
                opacity: _selectedRange == null ? .52 : 1,
                child: ExcludeFocus(
                  excluding: _selectedRange == null,
                  child: IgnorePointer(
                    ignoring: _selectedRange == null,
                    child: OpsDockSearchField(
                      controller: _queryController,
                      query: _query,
                      semanticLabel: '과거 로그 번호판 4자리 검색',
                      onChanged: _setQuery,
                      onClear: _clearQuery,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      maxLength: 4,
                      onSubmitted: (_) {
                        if (_canSearch) {
                          _searchHistory();
                        } else {
                          _log(
                            'search_submit_blocked rangeSelected=${_selectedRange != null} queryValid=$_queryValid networkRead=0',
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            CommonIconButton(
              icon: Icons.date_range_rounded,
              tooltip: '기간 선택',
              onPressed: _loading ? null : _pickRange,
              size: 40,
              iconSize: 19,
              haptic: CommonHaptic.selection,
            ),
            const SizedBox(width: 4),
            CommonIconButton(
              icon: Icons.search_rounded,
              tooltip: '이력 검색',
              onPressed: _canSearch ? _searchHistory : null,
              loading: _loading,
              size: 40,
              iconSize: 19,
              haptic: CommonHaptic.selection,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : CommonUiMotion.selection,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .08),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              _statusText,
              key: ValueKey<String>(_statusText),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: CommonUiTheme.of(context).textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: OpsDockResultSwitcher(child: body),
              ),
              OpsDockLoadingOverlay(loading: _loading),
            ],
          ),
        ),
        OpsDockContextFooterTransition(
          child: selected == null
              ? const SizedBox.shrink(
                  key: ValueKey<String>('history-footer-empty'),
                )
              : OpsDockContextFooter(
                  key: ValueKey<String>('history-footer-${selected.id}'),
                  children: [
                    Expanded(
                      child: CommonButton(
                        label: '사진',
                        icon: Icons.photo_rounded,
                        onPressed: () => widget.onOpenImage(
                          context,
                          selected.plateNumber.isEmpty
                              ? selected.docId.split('_').first
                              : selected.plateNumber,
                        ),
                        variant: CommonButtonVariant.secondary,
                        haptic: CommonHaptic.selection,
                        minHeight: 42,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.record,
    required this.selected,
    required this.formatDateTime,
    required this.formatWon,
  });

  final _HistoryRecord record;
  final bool selected;
  final String Function(DateTime?) formatDateTime;
  final String Function(num?) formatWon;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.plateNumber.isEmpty ? record.docId : record.plateNumber,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                record.date,
                style: textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                    ? Duration.zero
                    : CommonUiMotion.selection,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                  key: ValueKey<bool>(selected),
                  size: 18,
                  color: selected ? tokens.accent : tokens.iconSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${record.location ?? '—'} · ${formatDateTime(record.lastLogAt)} · ${formatWon(record.lockedFeeAmount)}',
            style: textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          AnimatedSize(
            duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                ? Duration.zero
                : CommonUiMotion.component,
            curve: CommonUiMotion.enter,
            alignment: Alignment.topCenter,
            child: selected
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Divider(height: 1, color: tokens.borderSubtle),
                      const SizedBox(height: 8),
                      _DetailLine(label: '상태', value: record.type ?? '—'),
                      _DetailLine(label: '정산 유형', value: record.billingType ?? '—'),
                      _DetailLine(label: '위치', value: record.location ?? '—'),
                      _DetailLine(label: '담당자', value: record.userName ?? '—'),
                      _DetailLine(label: '메모', value: record.customStatus ?? '—'),
                      _DetailLine(label: '확정 요금', value: formatWon(record.lockedFeeAmount)),
                      _DetailLine(label: '결제 수단', value: record.paymentMethod ?? '—'),
                      const SizedBox(height: 6),
                      _DetailLine(label: '기본 요금', value: formatWon(record.basicAmount)),
                      _DetailLine(label: '추가 요금', value: formatWon(record.addAmount)),
                      _DetailLine(label: '정규 요금', value: formatWon(record.regularAmount)),
                      _DetailLine(label: '사용자 조정', value: formatWon(record.userAdjustment)),
                      const SizedBox(height: 6),
                      _DetailLine(label: '요청', value: formatDateTime(record.requestTime)),
                      _DetailLine(label: '업데이트', value: formatDateTime(record.updatedAt)),
                      _DetailLine(label: '입차 완료', value: formatDateTime(record.parkingCompletedAt)),
                      _DetailLine(label: '출차 완료', value: formatDateTime(record.departureCompletedAt)),
                      if (record.logs.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '로그 ${record.logs.length}건',
                          style: textTheme.labelSmall?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        for (final log in record.logs.reversed.take(4))
                          _LogLine(log: log, formatDateTime: formatDateTime),
                      ],
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: style?.copyWith(color: tokens.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: style?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.log, required this.formatDateTime});

  final Map<String, dynamic> log;
  final String Function(DateTime?) formatDateTime;

  DateTime? _parse(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final action = log['action']?.toString().trim() ?? '';
    final by = log['performedBy']?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 14, color: tokens.iconSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              action.isEmpty ? '기록' : action,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (by.isNotEmpty) ...[
            Text(
              by,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            formatDateTime(_parse(log['timestamp'])),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _MutableHistoryRecord {
  _MutableHistoryRecord({required this.date, required this.docId});

  final String date;
  final String docId;
  final Map<String, dynamic> meta = <String, dynamic>{};
  final List<Map<String, dynamic>> logs = <Map<String, dynamic>>[];
  final Set<String> logSignatures = <String>{};

  void absorbMeta(Map<String, dynamic> values) {
    for (final entry in values.entries) {
      if (entry.value?.toString().trim().isNotEmpty == true) {
        meta[entry.key] = entry.value;
      }
    }
  }

  _HistoryRecord freeze(_DepartureCompletedHistoryWorkspaceState state) {
    logs.sort((a, b) {
      final at = state._parseTimestamp(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = state._parseTimestamp(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });
    String? lastString(List<String> keys) {
      for (var index = logs.length - 1; index >= 0; index--) {
        for (final key in keys) {
          final value = state._stringValue(logs[index][key]);
          if (value != null) return value;
        }
      }
      return null;
    }
    num? lastNumber(List<String> keys) {
      for (var index = logs.length - 1; index >= 0; index--) {
        for (final key in keys) {
          final value = state._parseNumber(logs[index][key]);
          if (value != null) return value;
        }
      }
      return null;
    }
    final plateNumber = state._stringValue(meta['plateNumber']) ??
        state._stringValue(meta['plate_number']) ??
        (docId.contains('_') ? docId.split('_').first : docId);
    final storedTail = state._stringValue(meta['plate_four_digit']) ??
        state._stringValue(meta['plateFourDigit']);
    return _HistoryRecord(
      id: '$date|$docId',
      date: date,
      docId: docId,
      plateNumber: plateNumber,
      tail4: state._tail4(plateNumber, docId, storedTail),
      billingType: state._stringValue(meta['billingType']),
      location: state._stringValue(meta['location']),
      userName: state._stringValue(meta['userName']),
      customStatus: state._stringValue(meta['customStatus']),
      type: state._stringValue(meta['type']),
      paymentMethod: state._stringValue(meta['paymentMethod']) ?? lastString(['paymentMethod']),
      lockedFeeAmount: state._parseNumber(meta['lockedFeeAmount']) ??
          state._parseNumber(meta['lockedFee']) ??
          lastNumber(['lockedFeeAmount', 'lockedFee']),
      basicAmount: state._parseNumber(meta['basicAmount']),
      addAmount: state._parseNumber(meta['addAmount']),
      regularAmount: state._parseNumber(meta['regularAmount']),
      userAdjustment: state._parseNumber(meta['userAdjustment']),
      requestTime: state._parseTimestamp(meta['request_time'] ?? meta['requestTime']),
      updatedAt: state._parseTimestamp(meta['updatedAt']),
      parkingCompletedAt: state._parseTimestamp(meta['parkingCompletedAt']),
      departureCompletedAt: state._parseTimestamp(meta['departureCompletedAt']),
      lastLogAt: logs.isEmpty ? null : state._parseTimestamp(logs.last['timestamp']),
      logs: List<Map<String, dynamic>>.unmodifiable(logs),
    );
  }
}

class _HistoryRecord {
  const _HistoryRecord({
    required this.id,
    required this.date,
    required this.docId,
    required this.plateNumber,
    required this.tail4,
    required this.billingType,
    required this.location,
    required this.userName,
    required this.customStatus,
    required this.type,
    required this.paymentMethod,
    required this.lockedFeeAmount,
    required this.basicAmount,
    required this.addAmount,
    required this.regularAmount,
    required this.userAdjustment,
    required this.requestTime,
    required this.updatedAt,
    required this.parkingCompletedAt,
    required this.departureCompletedAt,
    required this.lastLogAt,
    required this.logs,
  });

  final String id;
  final String date;
  final String docId;
  final String plateNumber;
  final String tail4;
  final String? billingType;
  final String? location;
  final String? userName;
  final String? customStatus;
  final String? type;
  final String? paymentMethod;
  final num? lockedFeeAmount;
  final num? basicAmount;
  final num? addAmount;
  final num? regularAmount;
  final num? userAdjustment;
  final DateTime? requestTime;
  final DateTime? updatedAt;
  final DateTime? parkingCompletedAt;
  final DateTime? departureCompletedAt;
  final DateTime? lastLogAt;
  final List<Map<String, dynamic>> logs;
}
