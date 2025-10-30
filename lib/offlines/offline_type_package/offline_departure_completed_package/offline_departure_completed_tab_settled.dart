import 'dart:convert';
import 'package:flutter/material.dart';

import '../../sql/offline_auth_db.dart';

import 'widgets/offline_departure_completed_page_merge_log.dart';
import 'widgets/offline_departure_completed_page_today_log.dart';
import '../../../utils/snackbar_helper.dart';

class OfflineDepartureCompletedTabSettled extends StatefulWidget {
  const OfflineDepartureCompletedTabSettled({
    super.key,
    required this.area,
    required this.division,
    required this.selectedDate,
    required this.plateNumber,
  });

  final String area;
  final String division;
  final DateTime selectedDate;
  final String plateNumber;

  @override
  State<OfflineDepartureCompletedTabSettled> createState() => _OfflineDepartureCompletedTabSettledState();
}

class _OfflineDepartureCompletedTabSettledState extends State<OfflineDepartureCompletedTabSettled> {
  bool _openToday = true;
  bool _openMerged = false;

  void _toggleToday() {
    setState(() {
      if (_openToday) {
        _openToday = false;
        _openMerged = false;
      } else {
        _openToday = true;
        _openMerged = false;
      }
    });
  }

  void _toggleMerged() {
    setState(() {
      if (_openMerged) {
        _openMerged = false;
        _openToday = false;
      } else {
        _openMerged = true;
        _openToday = false;
      }
    });
  }

  final TextEditingController _fourDigitCtrl = TextEditingController();
  bool _isLoading = false;
  bool _hasSearched = false;

  List<Map<String, Object?>> _resultsRows = [];
  int _selectedResultIndex = 0;

  TabController? _tabController;
  static const int _settledTabIndex = 1;

  bool _isValidFourDigit(String v) => RegExp(r'^\d{4}$').hasMatch(v);

  String _shortPlateLabel(String plate) {
    final idx = plate.indexOf('_');
    return idx == -1 ? plate : plate.substring(0, idx);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onTabChange() {
    if (_tabController == null) return;
    if (_tabController!.indexIsChanging) {
      final from = _tabController!.previousIndex;
      final to = _tabController!.index;
      if (from == _settledTabIndex && to != _settledTabIndex) {
        _resetSearchState();
      }
    }
  }

  void _resetSearchState() {
    if (!mounted) return;
    setState(() {
      _fourDigitCtrl.clear();
      _resultsRows = [];
      _hasSearched = false;
      _isLoading = false;
      _selectedResultIndex = 0;
    });
  }

  Future<void> _runSearch() async {
    final q = _fourDigitCtrl.text.trim();
    if (!_isValidFourDigit(q)) return;

    setState(() => _isLoading = true);

    try {
      final db = await OfflineAuthDb.instance.database;
      final rows = await db.query(
        OfflineAuthDb.tablePlates,
        columns: const [
          'id',
          'plate_number',
          'plate_four_digit',
          'area',
          'logs', // JSON 문자열
          'request_time',
          'is_locked_fee',
          'updated_at',
          'created_at',
        ],
        where: '''
          COALESCE(status_type,'') = ?
          AND LOWER(TRIM(area)) = LOWER(TRIM(?))
          AND COALESCE(plate_four_digit,'') = ?
        ''',
        whereArgs: ['departureCompleted', widget.area, q],
        orderBy: 'COALESCE(updated_at, created_at) DESC',
        limit: 50,
      );

      int initialIndex = 0;
      for (int i = 0; i < rows.length; i++) {
        final raw = rows[i]['logs'];
        if (raw is String && raw.trim().isNotEmpty) {
          try {
            final list = jsonDecode(raw);
            if (list is List && list.isNotEmpty) {
              initialIndex = i;
              break;
            }
          } catch (_) {
            /* ignore */
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _resultsRows = rows;
        _hasSearched = true;
        _isLoading = false;
        _selectedResultIndex = rows.isEmpty ? 0 : initialIndex;
        _openToday = true;
        _openMerged = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showFailedSnackbar(context, '검색 중 오류가 발생했습니다: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _fourDigitCtrl.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tabController = DefaultTabController.of(context);
      _tabController?.addListener(_onTabChange);
    });
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChange);
    _fourDigitCtrl.removeListener(_onTextChanged);
    _fourDigitCtrl.dispose();
    super.dispose();
  }

  // === Merged 섹션: 로더 구현 ===
  Future<List<DayBundle>> _mergedLoader({
    required String division,
    required String area,
    required DateTime start,
    required DateTime end,
  }) async {
    // 헬퍼들
    String yyyymmdd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    DateTime? parseTs(dynamic ts) {
      if (ts == null) return null;
      if (ts is int) {
        if (ts > 100000000000) return DateTime.fromMillisecondsSinceEpoch(ts);
        return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      }
      if (ts is String) return DateTime.tryParse(ts);
      return null;
    }

    bool isInRange(DateTime day, DateTime s, DateTime e) {
      final dd = DateTime(day.year, day.month, day.day);
      final ss = DateTime(s.year, s.month, s.day);
      final ee = DateTime(e.year, e.month, e.day);
      return !dd.isBefore(ss) && !dd.isAfter(ee);
    }

    final db = await OfflineAuthDb.instance.database;

    // area, status_type 기준으로 우선 조회(날짜는 Dart에서 필터)
    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const [
        'id',
        'plate_number',
        'area',
        'logs',        // JSON 배열 문자열 (각 원소에 timestamp 존재 가정)
        'request_time',// 보조 타임스탬프(없을 수 있음)
        'updated_at',
        'created_at',
      ],
      where: '''
        COALESCE(status_type,'') = ?
        AND LOWER(TRIM(area)) = LOWER(TRIM(?))
      ''',
      whereArgs: ['departureCompleted', area],
      orderBy: 'COALESCE(updated_at, created_at) ASC',
      // limit: 생략 (필요시 제한)
    );

    // ymd → docs
    final Map<String, List<DocBundle>> dayMap = {};

    for (final r in rows) {
      final plate = (r['plate_number'] as String?) ?? '';
      final idVal = r['id'];
      final docId = (idVal == null) ? plate : idVal.toString();

      // logs 파싱
      final List<Map<String, dynamic>> logs = () {
        final raw = r['logs'];
        if (raw is String && raw.trim().isNotEmpty) {
          try {
            final j = jsonDecode(raw);
            if (j is List) {
              return j
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
          } catch (_) {/* ignore */}
        }
        return <Map<String, dynamic>>[];
      }();

      // 시간 오름차순 정렬
      logs.sort((a, b) {
        final at = parseTs(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = parseTs(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return at.compareTo(bt);
      });

      // 기준 날짜: 마지막 로그의 날짜 → 없으면 request_time/updated_at/created_at 순으로 보조
      DateTime? basis = logs.isNotEmpty ? parseTs(logs.last['timestamp']) : null;
      basis ??= parseTs(r['request_time']);
      basis ??= parseTs(r['updated_at']);
      basis ??= parseTs(r['created_at']);

      if (basis == null) continue; // 날짜 판단 불가 데이터 건너뜀
      if (!isInRange(basis, start, end)) continue;

      final ymd = yyyymmdd(basis);
      final doc = DocBundle(docId: docId, plateNumber: plate, logs: logs);
      dayMap.putIfAbsent(ymd, () => <DocBundle>[]).add(doc);
    }

    // 날짜별 문서 정렬(마지막 로그 시각 기준 오름차순)
    final days = <DayBundle>[];
    final keys = dayMap.keys.toList()..sort();
    for (final ymd in keys) {
      final docs = dayMap[ymd]!..sort((a, b) {
        DateTime? parse(dynamic ts) {
          if (ts == null) return null;
          if (ts is int) {
            if (ts > 100000000000) return DateTime.fromMillisecondsSinceEpoch(ts);
            return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
          }
          if (ts is String) return DateTime.tryParse(ts);
          return null;
        }
        final at = a.logs.isNotEmpty ? parse(a.logs.last['timestamp']) : null;
        final bt = b.logs.isNotEmpty ? parse(b.logs.last['timestamp']) : null;
        return (at ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(bt ?? DateTime.fromMillisecondsSinceEpoch(0));
      });
      days.add(DayBundle(dateStr: ymd, docs: docs));
    }

    return days;
  }

  Widget _buildTodaySectionBody() {
    if (!_hasSearched) {
      return Center(
        child: Text('번호판 4자리를 입력 후 검색하세요.', style: TextStyle(color: Colors.grey[600])),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_resultsRows.isEmpty) {
      return Center(
        child: Text('검색 결과가 없습니다.', style: TextStyle(color: Colors.grey[600])),
      );
    }

    final chips = _resultsRows.asMap().entries.map((entry) {
      final i = entry.key;
      final p = entry.value;
      final selected = _selectedResultIndex == i;
      final pn = (p['plate_number'] as String?) ?? '';
      return Padding(
        padding: const EdgeInsets.only(right: 6.0),
        child: ChoiceChip(
          label: Text(_shortPlateLabel(pn)),
          selected: selected,
          onSelected: (v) {
            if (v) setState(() => _selectedResultIndex = i);
          },
        ),
      );
    }).toList();

    final safeIndex = _resultsRows.isNotEmpty
        ? _selectedResultIndex.clamp(0, _resultsRows.length - 1)
        : 0;
    final row = _resultsRows.isNotEmpty ? _resultsRows[safeIndex] : <String, Object?>{};

    final String plate = (row['plate_number'] as String?) ?? '';
    final List<dynamic> logsRaw = () {
      final raw = row['logs'];
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          final list = jsonDecode(raw);
          if (list is List) return list;
        } catch (_) {}
      }
      return const <dynamic>[];
    }();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_resultsRows.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
        Expanded(
          child: OfflineDepartureCompletedPageTodayLog(
            plateNumber: plate,
            logsRaw: logsRaw,
          ),
        ),
      ],
    );
  }

  Widget _buildMergedSectionBody() {
    return OfflineDepartureCompletedPageMergeLog(
      division: widget.division,
      area: widget.area,
      loader: _mergedLoader, // ✅ 필수 인자 주입
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchBar = SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _fourDigitCtrl,
              maxLength: 4,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                counterText: '',
                labelText: '번호판 4자리',
                hintText: '예) 1234',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _runSearch(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isLoading || !_isValidFourDigit(_fourDigitCtrl.text) ? null : _runSearch,
            icon: _isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: const Text('검색'),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          _SectionHeader(
            key: const ValueKey('today-header'),
            icon: Icons.receipt_long,
            title: '오늘 입차 로그',
            isOpen: _openToday,
            onTap: _toggleToday,
          ),
          const SizedBox(height: 6),
          if (_openToday)
            Expanded(
              child: _buildTodaySectionBody(),
            ),
          const SizedBox(height: 6),
          _SectionHeader(
            key: const ValueKey('merged-header'),
            icon: Icons.merge_type,
            title: '과거 입차 로그',
            isOpen: _openMerged,
            onTap: _toggleMerged,
          ),
          const SizedBox(height: 6),
          if (_openMerged)
            Expanded(
              child: _buildMergedSectionBody(),
            ),
          const SizedBox(height: 8),
          searchBar,
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool? isOpen;
  final VoidCallback? onTap;

  const _SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.isOpen,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chevron = (onTap != null) ? (isOpen == true ? Icons.expand_less : Icons.expand_more) : null;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (chevron != null) ...[
            const SizedBox(width: 8),
            Icon(chevron, size: 20, color: Colors.grey[700]),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: content,
      ),
    );
  }
}
