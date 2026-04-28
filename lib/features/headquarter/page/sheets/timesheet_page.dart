import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/auth/google_auth_session.dart';

enum TimesheetTab { attendance, breakTime }

Future<sheets.SheetsApi> _sheetsApi() async {
  final client = await GoogleAuthSession.instance.safeClient();
  return sheets.SheetsApi(client);
}

class TimesheetPage extends StatefulWidget {
  const TimesheetPage({super.key, this.initialTab = TimesheetTab.attendance});

  final TimesheetTab initialTab;

  @override
  State<TimesheetPage> createState() => _TimesheetPageState();
}

class _TimesheetPageState extends State<TimesheetPage>
    with SingleTickerProviderStateMixin {
  static const _prefsKey = 'hq_sheet_id';

  static const _base = Color(0xFF43A047);
  static const _dark = Color(0xFF2E7D32);
  static const _light = Color(0xFFA5D6A7);
  static const _fg = Colors.white;

  late final TabController _tabController;
  final _idCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  final PageController _pageCtrl = PageController(initialPage: 0);
  int _pageIndex = 0;

  late final ScrollController _sheetVController;

  List<List<String>> _allRows = [];
  List<List<String>> _viewRows = [];

  int? _idxRecordedDate;
  int? _idxUserName;
  int? _idxArea;

  String _nameInput = '';
  String? _areaInput;
  DateTime? _dateInput;

  String _nameQuery = '';
  String? _selectedArea;
  DateTime? _selectedDate;

  bool _searchApplied = false;

  List<String> _areaOptions = [];

  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _sheetVController = ScrollController();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.index,
    )..addListener(() {
        if (!_tabController.indexIsChanging) {
          _load();
        }
      });
    _restoreId();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _idCtrl.dispose();
    _pageCtrl.dispose();
    _sheetVController.dispose();
    super.dispose();
  }

  TimesheetTab get _currentTab => TimesheetTab.values[_tabController.index];

  String get _sheetName =>
      _currentTab == TimesheetTab.attendance ? '출퇴근기록' : '휴게기록';

  String get _pageTitle =>
      _currentTab == TimesheetTab.attendance ? '출/퇴근 시트' : '휴게시간 시트';

  Future<void> _restoreId() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_prefsKey) ?? '';
    setState(() => _idCtrl.text = v);
    if (v.isNotEmpty) _load();
  }

  Future<void> _load() async {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      setState(() {
        _error = '스프레드시트 ID를 입력하세요.';
        _allRows = [];
        _viewRows = [];
        _areaOptions = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = await _sheetsApi();

      final range = '$_sheetName!A1:G';
      final resp = await api.spreadsheets.values.get(id, range);
      final raw = resp.values ?? const [];
      final converted =
          raw.map((r) => r.map((c) => c?.toString() ?? '').toList()).toList();

      _allRows = converted;

      _searchApplied = false;

      _sortColumnIndex = null;
      _sortAscending = true;

      _detectHeaderColumns();
      _collectAreaOptions();
      _applyFilters();

      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, id);
    } catch (e) {
      setState(() {
        _error = '불러오기 실패: $e';
        _allRows = [];
        _viewRows = [];
        _areaOptions = [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');

  void _detectHeaderColumns() {
    _idxRecordedDate = null;
    _idxUserName = null;
    _idxArea = null;
    if (_allRows.isEmpty) return;

    final header = _allRows.first;
    for (var i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      if (_idxRecordedDate == null &&
          (h.contains('recordeddate') || h == 'date' || h.contains('날짜'))) {
        _idxRecordedDate = i;
      }
      if (_idxUserName == null &&
          (h.contains('username') || h == 'name' || h.contains('이름'))) {
        _idxUserName = i;
      }
      if (_idxArea == null && (h == 'area' || h.contains('지역'))) {
        _idxArea = i;
      }
    }

    _idxRecordedDate ??= 0;
    _idxUserName ??= (header.length > 3 ? 3 : 0);
    _idxArea ??= (header.length > 4 ? 4 : 0);
  }

  void _collectAreaOptions() {
    final Set<String> areas = {};
    if (_allRows.length <= 1) {
      _areaOptions = [];
      return;
    }
    for (var i = 1; i < _allRows.length; i++) {
      final row = _allRows[i];
      if (_idxArea! < row.length) {
        final a = row[_idxArea!].trim();
        if (a.isNotEmpty) areas.add(a);
      }
    }
    _areaOptions = areas.toList()..sort((a, b) => a.compareTo(b));
  }

  DateTime? _parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final ymd = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})');
    final m1 = ymd.firstMatch(s);
    if (m1 != null) {
      final y = int.tryParse(m1.group(1) ?? '');
      final m = int.tryParse(m1.group(2) ?? '');
      final d = int.tryParse(m1.group(3) ?? '');
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }

    final ymd2 = RegExp(r'^(\d{4})(\d{2})(\d{2})$');
    final m2 = ymd2.firstMatch(s);
    if (m2 != null) {
      final y = int.tryParse(m2.group(1) ?? '');
      final m = int.tryParse(m2.group(2) ?? '');
      final d = int.tryParse(m2.group(3) ?? '');
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }

    return null;
  }

  DateTime? _parseTime(String s) {
    try {
      final parts = s.split(':');
      if (parts.length < 2) return null;
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      return DateTime(2000, 1, 1, h, m);
    } catch (_) {
      return null;
    }
  }

  void _applyFilters() {
    if (_allRows.isEmpty) {
      setState(() => _viewRows = []);
      return;
    }
    final header = _allRows.first;
    final data =
        _allRows.length > 1 ? _allRows.sublist(1) : const <List<String>>[];

    bool matches(List<String> row) {
      if (!_searchApplied) return true;

      if (_nameQuery.isNotEmpty) {
        final cell = _idxUserName! < row.length ? row[_idxUserName!] : '';
        if (!cell.toLowerCase().contains(_nameQuery)) return false;
      }
      if (_selectedArea != null && _selectedArea!.isNotEmpty) {
        final cell = _idxArea! < row.length ? row[_idxArea!] : '';
        if (cell != _selectedArea) return false;
      }
      if (_selectedDate != null) {
        final cell =
            _idxRecordedDate! < row.length ? row[_idxRecordedDate!] : '';
        final parsed = _parseDate(cell);
        if (parsed == null ||
            parsed.year != _selectedDate!.year ||
            parsed.month != _selectedDate!.month ||
            parsed.day != _selectedDate!.day) {
          return false;
        }
      }
      return true;
    }

    final filtered = data.where(matches).toList();

    final sorted = _sortColumnIndex == null
        ? filtered
        : _sortedCopy(filtered, _sortColumnIndex!, _sortAscending);

    setState(() => _viewRows = [header, ...sorted]);
  }

  void _onSort(int originalColumnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = originalColumnIndex;
      _sortAscending = ascending;
    });

    if (_viewRows.length <= 1) return;
    final header = _viewRows.first;
    final body = _viewRows.sublist(1);
    final sorted = _sortedCopy(body, originalColumnIndex, ascending);
    setState(() {
      _viewRows = [header, ...sorted];
    });
  }

  List<List<String>> _sortedCopy(
      List<List<String>> source, int columnIndex, bool ascending) {
    int cmp(List<String> a, List<String> b) {
      final av = columnIndex < a.length ? a[columnIndex] : '';
      final bv = columnIndex < b.length ? b[columnIndex] : '';

      final ad = _parseDate(av);
      final bd = _parseDate(bv);
      if (ad != null && bd != null) {
        final r = ad.compareTo(bd);
        return ascending ? r : -r;
      }

      final at = _parseTime(av);
      final bt = _parseTime(bv);
      if (at != null && bt != null) {
        final r = at.compareTo(bt);
        return ascending ? r : -r;
      }

      final an = double.tryParse(av.replaceAll(',', ''));
      final bn = double.tryParse(bv.replaceAll(',', ''));
      if (an != null && bn != null) {
        final r = an.compareTo(bn);
        return ascending ? r : -r;
      }

      final r = av.toLowerCase().compareTo(bv.toLowerCase());
      return ascending ? r : -r;
    }

    final list = List<List<String>>.from(source);
    list.sort(cmp);
    return list;
  }

  void _runSearch() {
    setState(() {
      _nameQuery = _nameInput.trim().toLowerCase();
      _selectedArea = _areaInput;
      _selectedDate = _dateInput;
      _searchApplied = true;
    });
    _applyFilters();

    _pageCtrl.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _resetInputs() {
    setState(() {
      _nameInput = '';
      _areaInput = null;
      _dateInput = null;
      _searchApplied = false;
    });
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    final rowsCount = _viewRows.isEmpty ? 0 : (_viewRows.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48 + 1),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w600),
                labelColor: Colors.black87,
                indicatorColor: _base,
                tabs: const [
                  Tab(text: '출/퇴근'),
                  Tab(text: '휴게시간'),
                ],
              ),
              Container(height: 1, color: Colors.black.withOpacity(0.06)),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: '불러오기',
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            TextField(
              controller: _idCtrl,
              decoration: InputDecoration(
                labelText: '스프레드시트 ID',
                hintText: '예: 1AbCdEfGhIjK... (문서 URL 중간의 ID)',
                prefixIcon: const Icon(Icons.link_rounded, color: _base),
                isDense: true,
                filled: true,
                fillColor: _light.withOpacity(.20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _base.withOpacity(.25)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: _base, width: 1.2),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: '불러오기',
                      child: IconButton(
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.download_for_offline_rounded,
                            color: _dark),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    Tooltip(
                      message: '지우기',
                      child: IconButton(
                        onPressed: _loading ? null : () => _idCtrl.clear(),
                        icon: const Icon(Icons.clear, color: _dark),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: 10),
            if (_loading) const LinearProgressIndicator(color: _base),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 6),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                children: [
                  _SearchPage(
                    baseColor: _base,
                    fgColor: _fg,
                    areaOptions: _areaOptions,
                    nameInput: _nameInput,
                    areaInput: _areaInput,
                    dateInput: _dateInput,
                    onNameChanged: (v) => setState(() => _nameInput = v),
                    onAreaChanged: (v) => setState(() => _areaInput = v),
                    onDateChanged: (v) => setState(() => _dateInput = v),
                    onReset: _resetInputs,
                    onSearch: _runSearch,
                  ),
                  _SheetPage(
                    rows: _viewRows,
                    rowsCount: rowsCount,
                    pageIndex: _pageIndex,
                    onGoSearch: () => _pageCtrl.animateToPage(
                      0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    searchApplied: _searchApplied,
                    vController: _sheetVController,
                    sortColumnIndex: _sortColumnIndex,
                    sortAscending: _sortAscending,
                    onSort: _onSort,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPage extends StatelessWidget {
  const _SearchPage({
    required this.baseColor,
    required this.fgColor,
    required this.areaOptions,
    required this.nameInput,
    required this.areaInput,
    required this.dateInput,
    required this.onNameChanged,
    required this.onAreaChanged,
    required this.onDateChanged,
    required this.onReset,
    required this.onSearch,
  });

  final Color baseColor;
  final Color fgColor;

  final List<String> areaOptions;
  final String nameInput;
  final String? areaInput;
  final DateTime? dateInput;

  final ValueChanged<String> onNameChanged;
  final ValueChanged<String?> onAreaChanged;
  final ValueChanged<DateTime?> onDateChanged;

  final VoidCallback onReset;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  baseColor.withOpacity(.15),
                  baseColor.withOpacity(.05)
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: baseColor.withOpacity(.20)),
            ),
            child: Row(
              children: [
                Icon(Icons.tips_and_updates_rounded, color: baseColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '검색을 실행하면 1번(시트) 화면에 필터링된 결과만 표시됩니다.',
                    style:
                        text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              labelText: 'userName(이름)',
              prefixIcon: const Icon(Icons.person_outline_rounded),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (v) => onNameChanged(v.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: areaInput,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'area(지역)',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('전체')),
              ...areaOptions.map(
                (a) => DropdownMenuItem(
                  value: a,
                  child: Text(a, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: onAreaChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final first = DateTime(now.year - 2, 1, 1);
                    final last = DateTime(now.year + 2, 12, 31);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dateInput ?? now,
                      firstDate: first,
                      lastDate: last,
                    );
                    if (picked != null) {
                      onDateChanged(
                          DateTime(picked.year, picked.month, picked.day));
                    }
                  },
                  icon: const Icon(Icons.event),
                  label: Text(
                    dateInput == null
                        ? '날짜 선택'
                        : '${dateInput!.year}-${dateInput!.month.toString().padLeft(2, '0')}-${dateInput!.day.toString().padLeft(2, '0')}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '날짜 지우기',
                child: IconButton.outlined(
                  onPressed: () => onDateChanged(null),
                  icon: const Icon(Icons.clear),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('초기화'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.search),
                label: const Text('검색'),
                style: FilledButton.styleFrom(
                    backgroundColor: baseColor, foregroundColor: fgColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _SheetPage extends StatelessWidget {
  const _SheetPage({
    required this.rows,
    required this.rowsCount,
    required this.pageIndex,
    required this.onGoSearch,
    required this.searchApplied,
    required this.vController,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
  });

  final List<List<String>> rows;
  final int rowsCount;
  final int pageIndex;
  final VoidCallback onGoSearch;
  final bool searchApplied;
  final ScrollController vController;

  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int originalColumnIndex, bool ascending) onSort;

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');

  int? _findStatusIndex(List<String> header) {
    for (var i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      if (h == 'status' || h.contains('상태')) return i;
    }

    if (header.length >= 7) return 6;
    return null;
  }

  Set<int> _hiddenColumnIndices(List<String> header) {
    final hidden = <int>{};
    for (var i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      if (h == 'userid' || h.contains('userid')) hidden.add(i);
      if (h == 'division' || h.contains('division') || h.contains('부서')) {
        hidden.add(i);
      }
    }

    if (header.length >= 6) {
      if (!hidden.contains(2) && _norm(header[2]) == 'userid') hidden.add(2);
      if (!hidden.contains(5) && _norm(header[5]) == 'division') hidden.add(5);
    }
    return hidden;
  }

  Color? _rowColorByStatus(String statusRaw) {
    final s = statusRaw.trim();
    if (s == '출근') {
      return Colors.lightGreen.withOpacity(0.15);
    }
    if (s == '퇴근') {
      return Colors.orange.withOpacity(0.12);
    }
    if (s == '휴게') {
      return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('데이터가 없습니다.'));
    }

    final header = rows.first;
    final data = rows.length > 1 ? rows.sublist(1) : const <List<String>>[];

    final hiddenSet = _hiddenColumnIndices(header);
    final visibleIndices = <int>[
      for (int i = 0; i < header.length; i++)
        if (!hiddenSet.contains(i)) i
    ];

    int? visibleSortIndex;
    if (sortColumnIndex != null) {
      final idx = visibleIndices.indexOf(sortColumnIndex!);
      visibleSortIndex = idx >= 0 ? idx : null;
    }

    final statusIdx = _findStatusIndex(header);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('표시 행: $rowsCount',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const Spacer(),
            if (!searchApplied)
              TextButton.icon(
                onPressed: onGoSearch,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('검색으로 이동'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: (visibleIndices.length * 140).toDouble()),
              child: Scrollbar(
                controller: vController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  primary: false,
                  controller: vController,
                  child: DataTable(
                    sortColumnIndex: visibleSortIndex,
                    sortAscending: sortAscending,
                    columns: [
                      for (int vi = 0; vi < visibleIndices.length; vi++)
                        DataColumn(
                          label: Text(
                            header[visibleIndices[vi]],
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onSort: (visibleIndex, asc) =>
                              onSort(visibleIndices[visibleIndex], asc),
                        ),
                    ],
                    rows: [
                      for (final r in data)
                        DataRow(
                          color: MaterialStateProperty.resolveWith((_) {
                            if (statusIdx != null && statusIdx < r.length) {
                              return _rowColorByStatus(r[statusIdx]);
                            }
                            return null;
                          }),
                          cells: [
                            for (final colIdx in visibleIndices)
                              DataCell(
                                  Text(colIdx < r.length ? r[colIdx] : '')),
                          ],
                        ),
                    ],
                    headingRowHeight: 44,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 56,
                    dividerThickness: 0.6,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
