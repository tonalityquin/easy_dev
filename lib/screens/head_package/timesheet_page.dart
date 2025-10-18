// lib/screens/head_package/timesheet_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;

// OAuth (google_sign_in v7.x + extension v3.x)
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

import 'package:shared_preferences/shared_preferences.dart';

enum TimesheetTab { attendance, breakTime }

// ────────────────────────────────────────────────────────────
// OAuth 헬퍼
// ────────────────────────────────────────────────────────────

/// ✅ GCP “웹 애플리케이션” 클라이언트 ID (Android에선 serverClientId로 사용)
const String _kWebClientId =
    '470236709494-kgk29jdhi8ba25f7ujnqhpn8f22fhf25.apps.googleusercontent.com';

bool _gsInitialized = false;

Future<void> _ensureGsInitialized() async {
  if (_gsInitialized) return;
  try {
    // Android: 28444(DEVELOPER_ERROR) 회피를 위해 웹 클라ID를 serverClientId로 지정
    await GoogleSignIn.instance.initialize(serverClientId: _kWebClientId);
  } catch (_) {
    // 이미 초기화된 경우 등은 무시
  }
  _gsInitialized = true;
}

/// GoogleSignIn v7 이벤트 기반으로 로그인 완료 계정 획득
Future<GoogleSignInAccount> _waitForSignInEvent() async {
  final signIn = GoogleSignIn.instance;
  final completer = Completer<GoogleSignInAccount>();
  late final StreamSubscription sub;

  sub = signIn.authenticationEvents.listen((event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        if (!completer.isCompleted) completer.complete(event.user);
      case GoogleSignInAuthenticationEventSignOut():
        break;
    }
  }, onError: (e) {
    if (!completer.isCompleted) completer.completeError(e);
  });

  try {
    try {
      await signIn.attemptLightweightAuthentication(); // 무 UI 시도
    } catch (_) {}
    if (signIn.supportsAuthenticate()) {
      await signIn.authenticate(); // 필요 시 UI 인증
    }
    final user = await completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw Exception('Google 로그인 응답 시간 초과'),
    );
    return user;
  } finally {
    await sub.cancel();
  }
}

/// Sheets용 OAuth AuthClient (읽기 전용/읽기쓰기 분리 가능)
Future<auth.AuthClient> _getSheetsAuthClient({required bool write}) async {
  await _ensureGsInitialized();
  final scopes = write
      ? <String>[sheets.SheetsApi.spreadsheetsScope] // 읽기/쓰기
      : <String>[sheets.SheetsApi.spreadsheetsReadonlyScope]; // 읽기 전용

  final user = await _waitForSignInEvent();
  var authorization =
  await user.authorizationClient.authorizationForScopes(scopes);
  authorization ??= await user.authorizationClient.authorizeScopes(scopes);

  return authorization.authClient(scopes: scopes);
}

// ────────────────────────────────────────────────────────────
// 본문
// ────────────────────────────────────────────────────────────

class TimesheetPage extends StatefulWidget {
  const TimesheetPage({super.key, this.initialTab = TimesheetTab.attendance});

  final TimesheetTab initialTab;

  @override
  State<TimesheetPage> createState() => _TimesheetPageState();
}

class _TimesheetPageState extends State<TimesheetPage>
    with SingleTickerProviderStateMixin {
  // 저장 키(공용): 같은 ID를 출/퇴근 & 휴게시간 탭에서 사용
  static const _prefsKey = 'hq_sheet_id';

  // 팔레트(Company Calendar와 톤 맞춤)
  static const _base = Color(0xFF43A047);
  static const _dark = Color(0xFF2E7D32);
  static const _light = Color(0xFFA5D6A7);
  static const _fg = Colors.white;

  late final TabController _tabController;
  final _idCtrl = TextEditingController();

  // 로딩/에러
  bool _loading = false;
  String? _error;

  // PageView(0=검색, 1=시트)
  final PageController _pageCtrl = PageController(initialPage: 0);
  int _pageIndex = 0;

  // 시트(1번 페이지) 전용 세로 스크롤 컨트롤러
  late final ScrollController _sheetVController;

  // 전체 로우 & 뷰 로우
  // 시트 포맷 가정: 헤더 포함 (예: recordedDate, time, userId, userName, area, division, status)
  List<List<String>> _allRows = [];
  List<List<String>> _viewRows = [];

  // 헤더 컬럼 인덱스
  int? _idxRecordedDate;
  int? _idxUserName;
  int? _idxArea;

  // 필터 입력값(검색 페이지의 입력 상태)
  String _nameInput = '';
  String? _areaInput; // null=전체
  DateTime? _dateInput;

  // 실제 적용된 필터(‘검색’ 버튼 눌렀을 때 이 값으로 적용)
  String _nameQuery = '';
  String? _selectedArea;
  DateTime? _selectedDate;

  // 검색 적용 여부(적용 시에만 1번 페이지에서 필터링)
  bool _searchApplied = false;

  // area 옵션(데이터에서 수집)
  List<String> _areaOptions = [];

  // 정렬 상태(원본 헤더 인덱스 기준)
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

    auth.AuthClient? client;
    try {
      // ✅ OAuth로 인증된 클라이언트(읽기 전용 스코프) 생성
      client = await _getSheetsAuthClient(write: false);
      final api = sheets.SheetsApi(client);

      final range = '$_sheetName!A1:G'; // 탭에 따라 시트 범위 전환
      final resp = await api.spreadsheets.values.get(id, range);
      final raw = resp.values ?? const [];
      final converted =
      raw.map((r) => r.map((c) => c?.toString() ?? '').toList()).toList();

      _allRows = converted;

      // 새로 로드되면, 검색 미적용 상태로 초기화(요구사항: 검색 누를 때만 필터 적용)
      _searchApplied = false;

      // 컬럼 정렬 상태 초기화
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
      client?.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  // ───────────── 헤더/열 매핑 & 필터링 ─────────────

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
    // 못 찾으면 안전 기본값
    _idxRecordedDate ??= 0;
    _idxUserName ??= (header.length > 3 ? 3 : 0); // (날짜,시간,ID,이름,area,division,status) 가정
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

    // yyyy-mm-dd / yyyy.mm.dd / yyyy/mm/dd
    final ymd = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})');
    final m1 = ymd.firstMatch(s);
    if (m1 != null) {
      final y = int.tryParse(m1.group(1) ?? '');
      final m = int.tryParse(m1.group(2) ?? '');
      final d = int.tryParse(m1.group(3) ?? '');
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }

    // yyyyMMdd
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

  // 현재 필터 기준으로 _viewRows 구성 (+ 정렬 적용)
  void _applyFilters() {
    if (_allRows.isEmpty) {
      setState(() => _viewRows = []);
      return;
    }
    final header = _allRows.first;
    final data =
    _allRows.length > 1 ? _allRows.sublist(1) : const <List<String>>[];

    bool matches(List<String> row) {
      if (!_searchApplied) return true; // 검색 전에는 전체 노출

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

    // 정렬 상태가 있으면 필터 결과에 정렬 적용
    final sorted = _sortColumnIndex == null
        ? filtered
        : _sortedCopy(filtered, _sortColumnIndex!, _sortAscending);

    setState(() => _viewRows = [header, ...sorted]);
  }

  // ───────────── 정렬 로직 ─────────────

  void _onSort(int originalColumnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = originalColumnIndex;
      _sortAscending = ascending;
    });
    // 현재 뷰(_viewRows) 데이터(헤더 제외)를 정렬해서 갱신
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

      // 날짜 우선 비교
      final ad = _parseDate(av);
      final bd = _parseDate(bv);
      if (ad != null && bd != null) {
        final r = ad.compareTo(bd);
        return ascending ? r : -r;
      }

      // 시간 비교
      final at = _parseTime(av);
      final bt = _parseTime(bv);
      if (at != null && bt != null) {
        final r = at.compareTo(bt);
        return ascending ? r : -r;
      }

      // 숫자 비교(쉼표 제거)
      final an = double.tryParse(av.replaceAll(',', ''));
      final bn = double.tryParse(bv.replaceAll(',', ''));
      if (an != null && bn != null) {
        final r = an.compareTo(bn);
        return ascending ? r : -r;
      }

      // 문자열 비교
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

    // 검색 후 결과 페이지(1번)로 이동
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
      _searchApplied = false; // 검색 해제 → 전체 표시
    });
    _applyFilters();
  }

  // ───────────── UI ─────────────

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
            // ID 입력 (compact)
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
                        icon: const Icon(
                            Icons.download_for_offline_rounded,
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

            // 좌우 스와이프: 0=검색, 1=시트
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                children: [
                  // 0) 검색(필터) 화면
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

                  // 1) 시트 화면(검색 적용 시에만 필터 반영) + 정렬
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
                    vController: _sheetVController, // 전용 컨트롤러 전달
                    // 정렬 상태(원본 인덱스)
                    sortColumnIndex: _sortColumnIndex,
                    sortAscending: _sortAscending,
                    onSort: _onSort, // 헤더 클릭 정렬(원본 인덱스 전달)
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

// ────────────────────────────────────────────────────────────
// 0) 검색(필터) 페이지
// ────────────────────────────────────────────────────────────
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
      primary: false, // 기본 PrimaryScrollController 사용 안 함
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
                colors: [baseColor.withOpacity(.15), baseColor.withOpacity(.05)],
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
                    style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (v) => onNameChanged(v.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),

          // null=전체 선택 가능하도록 String? 제네릭 사용
          DropdownButtonFormField<String?>(
            value: areaInput,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'area(지역)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

// ────────────────────────────────────────────────────────────
// 1) 시트 페이지(정렬 + 컬럼 숨김 + 행 색상 구분)
// ────────────────────────────────────────────────────────────
class _SheetPage extends StatelessWidget {
  const _SheetPage({
    required this.rows,
    required this.rowsCount,
    required this.pageIndex,
    required this.onGoSearch,
    required this.searchApplied,
    required this.vController, // 시트 전용 세로 컨트롤러
    required this.sortColumnIndex, // 원본 인덱스
    required this.sortAscending,
    required this.onSort, // (원본 인덱스, asc) 콜백
  });

  final List<List<String>> rows;
  final int rowsCount;
  final int pageIndex;
  final VoidCallback onGoSearch;
  final bool searchApplied;
  final ScrollController vController;

  final int? sortColumnIndex; // 원본 헤더 인덱스
  final bool sortAscending;
  final void Function(int originalColumnIndex, bool ascending) onSort;

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');

  int? _findStatusIndex(List<String> header) {
    for (var i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      if (h == 'status' || h.contains('상태')) return i;
    }
    // 기본 포맷 가정: (날짜, 시간, userId, userName, area, division, status)
    if (header.length >= 7) return 6;
    return null;
  }

  /// 숨길 컬럼 인덱스 집합 생성: userId, division
  Set<int> _hiddenColumnIndices(List<String> header) {
    final hidden = <int>{};
    for (var i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      if (h == 'userid' || h.contains('userid')) hidden.add(i);
      if (h == 'division' || h.contains('division') || h.contains('부서')) {
        hidden.add(i);
      }
    }
    // 기본 포맷 보조: userId(2), division(5)
    if (header.length >= 6) {
      // 이미 탐지되지 않았다면 보조로 추가
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
      return null; // 기본(하얀색)
    }
    return null; // 기타도 기본
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('데이터가 없습니다.'));
    }

    final header = rows.first;
    final data = rows.length > 1 ? rows.sublist(1) : const <List<String>>[];

    // 숨김 컬럼 결정 및 가시 컬럼 인덱스 매핑
    final hiddenSet = _hiddenColumnIndices(header);
    final visibleIndices = <int>[
      for (int i = 0; i < header.length; i++) if (!hiddenSet.contains(i)) i
    ];

    // 정렬 인덱스(원본)를 가시 인덱스로 변환 (정렬 아이콘 표시용)
    int? visibleSortIndex;
    if (sortColumnIndex != null) {
      final idx = visibleIndices.indexOf(sortColumnIndex!);
      visibleSortIndex = idx >= 0 ? idx : null;
    }

    // status 컬럼 원본 인덱스
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
                            style:
                            const TextStyle(fontWeight: FontWeight.w700),
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
                              DataCell(Text(colIdx < r.length ? r[colIdx] : '')),
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
