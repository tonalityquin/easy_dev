import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/location/location_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';

import 'ui/minor_reverse_page_top_sheet.dart';
import '../../../../../../screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

const String _kLocationAll = '전체';

/// ✅ (분리) 출차 요청 "실시간(view) 탭" 진입 게이트(ON/OFF)
class DepartureRequestsRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'departure_requests_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyRealtimeTabEnabled) ?? false; // 기본 OFF
  }

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, v);
  }
}

/// ✅ (분리) 입차 요청 "실시간(view) 탭" 진입 게이트(ON/OFF)
class ParkingRequestsRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'parking_requests_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyRealtimeTabEnabled) ?? false; // 기본 OFF
  }

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, v);
  }
}

/// ✅ (분리) 입차 완료 "실시간(view) 탭" 진입 게이트(ON/OFF)
/// - ✅ 기존 키 유지(하위 호환)
class ParkingCompletedRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'parking_completed_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyRealtimeTabEnabled) ?? false; // 기본 OFF
  }

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, v);
  }
}

/// 👉 역 Top Sheet로 "출차 요청(view) / 입차 요청(view) / 입차 완료(view)" 테이블 열기
Future<void> showMinorParkingCompletedTableTopSheet(BuildContext context) async {
  final userArea = context.read<UserState>().currentArea.trim();
  final stateArea = context.read<AreaState>().currentArea.trim();
  final area = userArea.isNotEmpty ? userArea : stateArea;

  if (area.isEmpty) {
    showFailedSnackbar(context, '현재 지역(currentArea)이 설정되지 않았습니다.');
    return;
  }

  await showMinorReversePageTopSheet(
    context: context,
    maxHeightFactor: 0.95,
    builder: (_) => MinorParkingCompletedTableSheet(area: area),
  );
}

/// Deep Blue 팔레트(기존 컨셉 유지)
class _Palette {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

/// 3개 타입(탭)
enum _TabMode {
  departureRequestsRealtime, // 출차 요청(view)
  parkingRequestsRealtime, // 입차 요청(view)
  parkingCompletedRealtime, // 입차 완료(view)
}

/// UI 렌더링 Row VM
class _RowVM {
  final String plateNumber;
  final String location;
  final DateTime? createdAt;

  const _RowVM({
    required this.plateNumber,
    required this.location,
    required this.createdAt,
  });
}

/// ─────────────────────────────────────────────────────────
/// GlobalKey 대체: 탭 컨트롤러(탭 탭 시 refresh를 부모에서 호출)
/// ─────────────────────────────────────────────────────────
class _RealtimeTabController {
  Future<void> Function()? _refreshUser;

  void _bindRefresh(Future<void> Function() refreshUser) {
    _refreshUser = refreshUser;
  }

  void _unbind() {
    _refreshUser = null;
  }

  bool get isBound => _refreshUser != null;

  Future<void> refreshUser() async {
    final f = _refreshUser;
    if (f == null) return;
    await f();
  }
}

/// ─────────────────────────────────────────────────────────
/// Firestore view repository 공통 인터페이스
/// ─────────────────────────────────────────────────────────
abstract class _BaseViewRepository {
  String get collection;
  String get prefsKeyWriteEnabled;
  String get primaryTimeField;

  List<_RowVM> getCached(String area);

  bool isRefreshBlocked(String area);
  int refreshRemainingSec(String area);
  void startRefreshCooldown(String area, Duration d);

  Future<void> ensureWriteToggleLoaded();
  bool get isRealtimeWriteEnabled;
  Future<void> setRealtimeWriteEnabled(bool v);

  Future<List<_RowVM>> fetchFromServerAndCache(String area);
}

/// ─────────────────────────────────────────────────────────
/// 제너릭 view repository (3개 탭 공용)
/// ─────────────────────────────────────────────────────────
class _GenericViewRepository implements _BaseViewRepository {
  @override
  final String collection;

  @override
  final String prefsKeyWriteEnabled;

  @override
  final String primaryTimeField;

  final FirebaseFirestore _firestore;

  _GenericViewRepository({
    required this.collection,
    required this.prefsKeyWriteEnabled,
    required this.primaryTimeField,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static final Map<String, List<_RowVM>> _cacheByKey = <String, List<_RowVM>>{};
  static final Map<String, DateTime> _refreshBlockedUntilByKey =
  <String, DateTime>{};

  static SharedPreferences? _prefs;
  static bool _prefsLoaded = false;
  static final Map<String, bool> _realtimeWriteEnabledByPrefsKey =
  <String, bool>{};

  String _k(String area) => '$collection|${area.trim()}';

  @override
  List<_RowVM> getCached(String area) {
    final k = _k(area);
    return List<_RowVM>.of(_cacheByKey[k] ?? const <_RowVM>[]);
  }

  @override
  bool isRefreshBlocked(String area) {
    final k = _k(area);
    final until = _refreshBlockedUntilByKey[k];
    return until != null && DateTime.now().isBefore(until);
  }

  @override
  int refreshRemainingSec(String area) {
    if (!isRefreshBlocked(area)) return 0;
    final k = _k(area);
    final until = _refreshBlockedUntilByKey[k]!;
    final s = until.difference(DateTime.now()).inSeconds;
    return s < 0 ? 0 : s + 1;
  }

  @override
  void startRefreshCooldown(String area, Duration d) {
    final a = area.trim();
    if (a.isEmpty) return;
    final k = _k(a);
    _refreshBlockedUntilByKey[k] = DateTime.now().add(d);
  }

  @override
  Future<void> ensureWriteToggleLoaded() async {
    if (!_prefsLoaded) {
      _prefs = await SharedPreferences.getInstance();
      _prefsLoaded = true;
    }
    _realtimeWriteEnabledByPrefsKey[prefsKeyWriteEnabled] =
        _prefs!.getBool(prefsKeyWriteEnabled) ?? false;
  }

  @override
  bool get isRealtimeWriteEnabled =>
      _realtimeWriteEnabledByPrefsKey[prefsKeyWriteEnabled] ?? false;

  @override
  Future<void> setRealtimeWriteEnabled(bool v) async {
    await ensureWriteToggleLoaded();
    _realtimeWriteEnabledByPrefsKey[prefsKeyWriteEnabled] = v;
    await _prefs!.setBool(prefsKeyWriteEnabled, v);
  }

  DateTime? _toDate(dynamic v) => (v is Timestamp) ? v.toDate() : null;

  String _normalizeLocation(String? raw) {
    final v = (raw ?? '').trim();
    return v.isEmpty ? '미지정' : v;
  }

  String _fallbackPlateFromDocId(String docId) {
    final idx = docId.lastIndexOf('_');
    if (idx > 0) return docId.substring(0, idx);
    return docId;
  }

  @override
  Future<List<_RowVM>> fetchFromServerAndCache(String area) async {
    final a = area.trim();
    if (a.isEmpty) return const <_RowVM>[];

    final docSnap = await _firestore.collection(collection).doc(a).get();
    final out = <_RowVM>[];

    if (!docSnap.exists) {
      _cacheByKey[_k(a)] = const <_RowVM>[];
      return const <_RowVM>[];
    }

    final data = docSnap.data() ?? <String, dynamic>{};
    final items = data['items'];

    if (items is Map) {
      for (final entry in items.entries) {
        final plateDocId = entry.key?.toString() ?? '';
        final v = entry.value;

        if (v is! Map) continue;
        final m = Map<String, dynamic>.from(v);

        final plateNumber =
            (m['plateNumber'] as String?) ?? _fallbackPlateFromDocId(plateDocId);
        final location = _normalizeLocation(m['location'] as String?);

        final createdAt =
            _toDate(m[primaryTimeField]) ?? _toDate(m['updatedAt']);

        if (plateNumber.isEmpty) continue;

        out.add(
          _RowVM(
            plateNumber: plateNumber,
            location: location,
            createdAt: createdAt,
          ),
        );
      }
    }

    _cacheByKey[_k(a)] = List<_RowVM>.of(out);
    return out;
  }
}

class MinorParkingCompletedTableSheet extends StatefulWidget {
  final String area;

  const MinorParkingCompletedTableSheet({
    super.key,
    required this.area,
  });

  @override
  State<MinorParkingCompletedTableSheet> createState() =>
      _MinorParkingCompletedTableSheetState();
}

class _MinorParkingCompletedTableSheetState
    extends State<MinorParkingCompletedTableSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _depGate = false;
  bool _reqGate = false;
  bool _pcGate = false;
  bool _gatesLoaded = false;

  // 탭별 refresh 바인딩(갱신 버튼 삭제 -> 탭 탭 시 갱신)
  final _RealtimeTabController _depCtrl = _RealtimeTabController();
  final _RealtimeTabController _reqCtrl = _RealtimeTabController();
  final _RealtimeTabController _pcCtrl = _RealtimeTabController();

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  @override
  void initState() {
    super.initState();

    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    _loadGates();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  int _firstEnabledTabOr(int fallback) {
    if (_depGate) return 0;
    if (_reqGate) return 1;
    if (_pcGate) return 2;
    return fallback;
  }

  Future<void> _loadGates() async {
    try {
      final dep = await DepartureRequestsRealtimeTabGate.isEnabled();
      final req = await ParkingRequestsRealtimeTabGate.isEnabled();
      final pc = await ParkingCompletedRealtimeTabGate.isEnabled();

      if (!mounted) return;

      setState(() {
        _depGate = dep;
        _reqGate = req;
        _pcGate = pc;
        _gatesLoaded = true;

        // 기본 진입: 가능한 첫 탭
        _tabCtrl.index = _firstEnabledTabOr(0);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _depGate = false;
        _reqGate = false;
        _pcGate = false;
        _gatesLoaded = true;
        _tabCtrl.index = 0;
      });
    }
  }

  String _titleForIndex(int idx) {
    if (idx == 0) return '출차 요청 테이블';
    if (idx == 1) return '입차 요청 테이블';
    return '입차 완료 테이블';
  }

  bool _isTabEnabled(int idx) {
    if (idx == 0) return _depGate;
    if (idx == 1) return _reqGate;
    return _pcGate;
  }

  _RealtimeTabController _controllerForIndex(int idx) {
    if (idx == 0) return _depCtrl;
    if (idx == 1) return _reqCtrl;
    return _pcCtrl;
  }

  // ✅ 탭 탭 시 해당 탭 갱신 (갱신 버튼 삭제 대체)
  void _requestRefreshForIndex(int index) {
    final ctrl = _controllerForIndex(index);

    // TabBarView가 해당 탭 위젯을 아직 만들기 전(바인딩 전)일 수 있으므로:
    // 1) post-frame에서 1차 시도
    // 2) 아직 바인딩이 아니면 짧은 딜레이 후 1회 재시도
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_gatesLoaded) return;
      if (!_isTabEnabled(index)) return;

      if (ctrl.isBound) {
        await ctrl.refreshUser();
        return;
      }

      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      if (!_gatesLoaded) return;
      if (!_isTabEnabled(index)) return;

      await ctrl.refreshUser();
    });
  }

  void _onTapTab(int index) {
    final tabName = (index == 0)
        ? 'departure_requests'
        : (index == 1)
        ? 'parking_requests'
        : 'parking_completed';

    _trace(
      '리버스 테이블 하단 탭 클릭(탭=갱신)',
      meta: <String, dynamic>{
        'screen': 'minor_reverse_table_sheet',
        'action': 'tab_tap_refresh',
        'tabIndex': index,
        'tab': tabName,
        'departureRequestsEnabled': _depGate,
        'parkingRequestsEnabled': _reqGate,
        'parkingCompletedEnabled': _pcGate,
        'area': widget.area,
      },
    );

    if (!_gatesLoaded) {
      showSelectedSnackbar(context, '설정 확인 중입니다.');
      return;
    }

    if (!_isTabEnabled(index)) {
      HapticFeedback.selectionClick();
      showSelectedSnackbar(context, '해당 탭이 비활성화되어 있습니다. 설정에서 ON 후 사용해 주세요.');
      _tabCtrl.animateTo(_firstEnabledTabOr(_tabCtrl.index));
      return;
    }

    // ✅ 탭을 누르면(선택/재선택 모두) 해당 탭을 갱신
    _requestRefreshForIndex(index);
  }

  Widget _tabLabel({
    required String text,
    required bool enabled,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!enabled) ...[
          Icon(Icons.lock_outline, size: 16, color: cs.outline.withOpacity(.9)),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildTopHeader(TextTheme textTheme, ColorScheme cs) {
    final title = _titleForIndex(_tabCtrl.index);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _Palette.base.withOpacity(.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.table_chart_outlined,
              color: _Palette.base,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _Palette.dark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '지역: ${widget.area}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: cs.outline),
                ),
              ],
            ),
          ),
          if (!_gatesLoaded) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(_Palette.base.withOpacity(.9)),
              ),
            ),
          ],
          const SizedBox(width: 6),
          IconButton(
            tooltip: '닫기',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  // ✅ 하단 바: 탭만 존재 (갱신 버튼 삭제)
  Widget _buildBottomBar(ColorScheme cs) {
    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: cs.outline.withOpacity(.15))),
        ),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: _Palette.base.withOpacity(.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _Palette.light.withOpacity(.25)),
          ),
          child: TabBar(
            controller: _tabCtrl,
            onTap: _onTapTab,
            labelColor: _Palette.base,
            unselectedLabelColor: cs.outline,
            indicatorColor: _Palette.base,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            tabs: [
              Tab(child: _tabLabel(text: '출차 요청', enabled: _depGate)),
              Tab(child: _tabLabel(text: '입차 요청', enabled: _reqGate)),
              Tab(child: _tabLabel(text: '입차 완료', enabled: _pcGate)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: true,
      left: false,
      right: false,
      bottom: false,
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            _buildTopHeader(textTheme, cs),
            const Divider(height: 1),

            // 탭 본문
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: const PageScrollPhysics(),
                children: [
                  _depGate
                      ? _UnifiedTableTab(
                    controller: _depCtrl,
                    mode: _TabMode.departureRequestsRealtime,
                    description: '탭을 누르면 해당 데이터가 갱신됩니다. 잦은 갱신은 앱에 무리를 줍니다.',
                  )
                      : const _RealtimeTabLockedPanel(
                    title: '출차 요청 실시간 탭이 비활성화되어 있습니다',
                    message: '설정에서 “출차 요청 실시간 모드(탭) 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
                  ),
                  _reqGate
                      ? _UnifiedTableTab(
                    controller: _reqCtrl,
                    mode: _TabMode.parkingRequestsRealtime,
                    description: '탭을 누르면 해당 데이터가 갱신됩니다. 잦은 갱신은 앱에 무리를 줍니다.',
                  )
                      : const _RealtimeTabLockedPanel(
                    title: '입차 요청 실시간 탭이 비활성화되어 있습니다',
                    message: '설정에서 “입차 요청 실시간 모드(탭) 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
                  ),
                  _pcGate
                      ? _UnifiedTableTab(
                    controller: _pcCtrl,
                    mode: _TabMode.parkingCompletedRealtime,
                    description: '탭을 누르면 해당 데이터가 갱신됩니다. 잦은 갱신은 앱에 무리를 줍니다.',
                  )
                      : const _RealtimeTabLockedPanel(
                    title: '입차 완료 실시간 탭이 비활성화되어 있습니다',
                    message: '설정에서 “입차 완료 실시간 모드(탭) 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
                  ),
                ],
              ),
            ),

            // ✅ 하단 고정 바(탭만)
            _buildBottomBar(cs),
          ],
        ),
      ),
    );
  }
}

class _RealtimeTabLockedPanel extends StatelessWidget {
  final String title;
  final String message;

  const _RealtimeTabLockedPanel({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 44, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: _Palette.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: cs.outline,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────
/// 통합 탭(뷰 전용 3종)
/// ─────────────────────────────────────────────────────────
class _UnifiedTableTab extends StatefulWidget {
  final _RealtimeTabController controller;
  final _TabMode mode;
  final String description;

  const _UnifiedTableTab({
    required this.controller,
    required this.mode,
    required this.description,
  });

  @override
  State<_UnifiedTableTab> createState() => _UnifiedTableTabState();
}

class _UnifiedTableTabState extends State<_UnifiedTableTab>
    with AutomaticKeepAliveClientMixin {
  late final _GenericViewRepository _repo;

  bool _loading = false;
  bool _hasFetchedFromServer = false;

  List<_RowVM> _allRows = <_RowVM>[];
  List<_RowVM> _rows = <_RowVM>[];

  // 검색/필터
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  static const int _debounceMs = 250;

  static const String _locationAll = _kLocationAll;
  String _selectedLocation = _locationAll;
  List<String> _availableLocations = <String>[];

  // 정렬
  bool _sortOldFirst = true;

  // 스크롤
  final ScrollController _scrollCtrl = ScrollController();

  // 쿨다운 표시
  Timer? _cooldownTicker;

  // write toggle
  bool _writeToggleLoading = false;

  String get _primaryTimeField {
    if (widget.mode == _TabMode.departureRequestsRealtime) return 'departureRequestedAt';
    if (widget.mode == _TabMode.parkingRequestsRealtime) return 'parkingRequestedAt';
    return 'parkingCompletedAt';
  }

  String get _timeHeaderLabel {
    if (widget.mode == _TabMode.departureRequestsRealtime) return 'Request';
    if (widget.mode == _TabMode.parkingRequestsRealtime) return 'Entry Req';
    return 'Entry';
  }

  String get _collection {
    if (widget.mode == _TabMode.departureRequestsRealtime) return 'departure_requests_view';
    if (widget.mode == _TabMode.parkingRequestsRealtime) return 'parking_requests_view';
    return 'parking_completed_view';
  }

  String get _prefsKeyWriteEnabled {
    if (widget.mode == _TabMode.departureRequestsRealtime) {
      return 'departure_requests_realtime_write_enabled_v1';
    }
    if (widget.mode == _TabMode.parkingRequestsRealtime) {
      return 'parking_requests_realtime_write_enabled_v1';
    }
    return 'parking_completed_realtime_write_enabled_v1';
  }

  String get _currentArea {
    final a1 = context.read<UserState>().currentArea.trim();
    final a2 = context.read<AreaState>().currentArea.trim();
    return a1.isNotEmpty ? a1 : a2;
  }

  bool get _isRefreshBlocked => _repo.isRefreshBlocked(_currentArea);
  int get _refreshRemainingSec => _repo.refreshRemainingSec(_currentArea);

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _repo = _GenericViewRepository(
      collection: _collection,
      prefsKeyWriteEnabled: _prefsKeyWriteEnabled,
      primaryTimeField: _primaryTimeField,
    );

    // ✅ 탭 탭 시 부모가 호출할 refresh 바인딩
    widget.controller._bindRefresh(_refreshFromTabTap);

    _searchCtrl.addListener(_onSearchChangedDebounced);

    // 캐시 즉시 렌더
    _allRows = List<_RowVM>.of(_repo.getCached(_currentArea));
    _availableLocations = _extractLocations(_allRows);
    _applyFilterAndSort();
    _syncLocationPickerCountsFromRows(_allRows);

    _ensureCooldownTicker();
    _loadRealtimeWriteToggle();
  }

  @override
  void dispose() {
    widget.controller._unbind();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _cooldownTicker?.cancel();
    super.dispose();
  }

  Future<void> _loadRealtimeWriteToggle() async {
    setState(() => _writeToggleLoading = true);
    try {
      await _repo.ensureWriteToggleLoaded();
    } catch (_) {
      // no-op
    } finally {
      if (!mounted) return;
      setState(() => _writeToggleLoading = false);
    }
  }

  void _onSearchChangedDebounced() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (!mounted) return;
      setState(() => _applyFilterAndSort());
    });
  }

  void _ensureCooldownTicker() {
    _cooldownTicker?.cancel();
    if (!_isRefreshBlocked) return;

    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!_isRefreshBlocked) t.cancel();
      setState(() {});
    });
  }

  // ✅ “탭을 탭하면” 갱신됨 (갱신 버튼 제거 대체)
  Future<void> _refreshFromTabTap() async {
    _trace(
      '탭 탭 갱신',
      meta: <String, dynamic>{
        'screen': 'minor_reverse_table_sheet',
        'action': 'tab_tap_refresh',
        'mode': widget.mode.toString(),
        'collection': _collection,
        'area': _currentArea,
        'loading': _loading,
        'blocked': _isRefreshBlocked,
        'remainingSec': _refreshRemainingSec,
        'hasFetchedFromServer': _hasFetchedFromServer,
      },
    );

    if (_loading) {
      showSelectedSnackbar(context, '이미 갱신 중입니다.');
      return;
    }

    if (_isRefreshBlocked) {
      _ensureCooldownTicker();
      showSelectedSnackbar(context, '새로고침 대기 중: ${_refreshRemainingSec}초');
      return;
    }

    _repo.startRefreshCooldown(_currentArea, const Duration(seconds: 30));
    _ensureCooldownTicker();

    setState(() => _loading = true);

    try {
      final rows = await _repo.fetchFromServerAndCache(_currentArea);

      _syncLocationPickerCountsFromRows(rows);

      if (!mounted) return;
      setState(() {
        _allRows = List<_RowVM>.of(rows);
        _availableLocations = _extractLocations(_allRows);

        if (_selectedLocation != _locationAll &&
            !_availableLocations.contains(_selectedLocation)) {
          _selectedLocation = _locationAll;
        }

        _applyFilterAndSort();
        _loading = false;
        _hasFetchedFromServer = true;
      });

      showSuccessSnackbar(context, '실시간 데이터를 갱신했습니다. ($_currentArea)');
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFailedSnackbar(context, '실시간 갱신 실패: $e');
    }
  }

  List<String> _extractLocations(List<_RowVM> rows) {
    final set = <String>{};
    for (final r in rows) {
      final k = r.location.trim();
      if (k.isNotEmpty) set.add(k);
    }
    final list = set.toList()..sort();
    return list;
  }

  void _applyFilterAndSort() {
    final search = _searchCtrl.text.trim().toLowerCase();

    _rows = _allRows.where((r) {
      if (_selectedLocation != _locationAll) {
        if (r.location != _selectedLocation) return false;
      }

      if (search.isNotEmpty) {
        final hit = r.plateNumber.toLowerCase().contains(search) ||
            r.location.toLowerCase().contains(search);
        if (!hit) return false;
      }

      return true;
    }).toList();

    _rows.sort((a, b) {
      final ca = a.createdAt;
      final cb = b.createdAt;
      if (ca == null && cb == null) return 0;
      if (ca == null) return _sortOldFirst ? 1 : -1;
      if (cb == null) return _sortOldFirst ? -1 : 1;
      final cmp = ca.compareTo(cb);
      return _sortOldFirst ? cmp : -cmp;
    });
  }

  void _toggleSortByCreatedAt() {
    setState(() {
      _sortOldFirst = !_sortOldFirst;
      _applyFilterAndSort();
    });
    showSelectedSnackbar(
      context,
      _sortOldFirst ? '시각: 오래된 순으로 정렬' : '시각: 최신 순으로 정렬',
    );
  }

  Future<void> _toggleRealtimeWriteEnabled(bool v) async {
    if (_writeToggleLoading) return;

    setState(() => _writeToggleLoading = true);
    try {
      await _repo.setRealtimeWriteEnabled(v);
      if (!mounted) return;
      showSelectedSnackbar(
        context,
        v
            ? '이 기기에서 실시간 데이터 삽입(Write)을 ON 했습니다.'
            : '이 기기에서 실시간 데이터 삽입(Write)을 OFF 했습니다.',
      );
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '설정 저장 실패: $e');
    } finally {
      if (!mounted) return;
      setState(() => _writeToggleLoading = false);
    }
  }

  // locationState plateCount 동기화(기존 컨셉 유지)
  Map<String, int>? _pendingPlateCountsByDisplayName;
  bool _plateCountsApplyScheduled = false;
  Map<String, int>? _lastAppliedPlateCountsByDisplayName;

  bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  void _scheduleApplyPlateCountsAfterFrame(Map<String, int> countsByDisplayName) {
    _pendingPlateCountsByDisplayName = countsByDisplayName;

    if (_plateCountsApplyScheduled) return;
    _plateCountsApplyScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _plateCountsApplyScheduled = false;
      if (!mounted) return;

      final toApply = _pendingPlateCountsByDisplayName;
      _pendingPlateCountsByDisplayName = null;
      if (toApply == null) return;

      if (_lastAppliedPlateCountsByDisplayName != null &&
          _mapsEqual(_lastAppliedPlateCountsByDisplayName!, toApply)) {
        return;
      }

      _lastAppliedPlateCountsByDisplayName = Map<String, int>.of(toApply);

      try {
        final locationState = context.read<LocationState>();
        locationState.updatePlateCounts(toApply);
      } catch (_) {}
    });
  }

  String _leafFromRowLocation(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final idx = v.lastIndexOf(' - ');
    if (idx >= 0) return v.substring(idx + 3).trim();
    return v;
  }

  void _syncLocationPickerCountsFromRows(List<_RowVM> rows, {int attempt = 0}) {
    if (!mounted) return;

    LocationState locationState;
    try {
      locationState = context.read<LocationState>();
    } catch (_) {
      return;
    }

    final locations = locationState.locations;

    if (locations.isEmpty) {
      if (attempt < 10) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          _syncLocationPickerCountsFromRows(rows, attempt: attempt + 1);
        });
      }
      return;
    }

    final rawCounts = <String, int>{};
    final leafCounts = <String, int>{};

    for (final r in rows) {
      final raw = r.location.trim();
      if (raw.isEmpty) continue;

      rawCounts[raw] = (rawCounts[raw] ?? 0) + 1;

      final leaf = _leafFromRowLocation(raw);
      if (leaf.isNotEmpty) {
        leafCounts[leaf] = (leafCounts[leaf] ?? 0) + 1;
      }
    }

    final countsByDisplayName = <String, int>{};

    for (final loc in locations) {
      final leaf = loc.locationName.trim();
      final parent = (loc.parent ?? '').trim();
      final displayName = loc.type == 'composite'
          ? (parent.isEmpty ? leaf : '$parent - $leaf')
          : leaf;

      countsByDisplayName[displayName] =
          rawCounts[displayName] ?? leafCounts[leaf] ?? 0;
    }

    _scheduleApplyPlateCountsAfterFrame(countsByDisplayName);
  }

  Widget _buildRowsChip(TextTheme text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.list_alt_outlined, size: 16, color: _Palette.base),
          const SizedBox(width: 6),
          Text(
            'Rows: ${_rows.length}',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCooldownChip(ColorScheme cs, TextTheme text) {
    final blocked = _isRefreshBlocked;
    final label = blocked ? '대기 ${_refreshRemainingSec}s' : 'Ready';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: blocked
            ? Colors.orange.withOpacity(.12)
            : Colors.teal.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            blocked ? Icons.timer_outlined : Icons.check_circle_outline,
            size: 16,
            color: blocked ? Colors.orange.shade800 : Colors.teal.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: text.labelMedium?.copyWith(
              color: blocked ? Colors.orange.shade800 : Colors.teal.shade700,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeLocationFilter(ColorScheme cs, TextTheme text) {
    final disabled = _loading || _availableLocations.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Palette.light.withOpacity(.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.place_outlined, size: 16, color: _Palette.base),
          const SizedBox(width: 6),
          Text(
            '주차구역:',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedLocation,
                isDense: true,
                isExpanded: true,
                icon: Icon(Icons.expand_more, color: cs.outline),
                items: <String>[_locationAll, ..._availableLocations].map((v) {
                  return DropdownMenuItem<String>(
                    value: v,
                    child: Text(
                      v,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(
                        color: disabled ? cs.outline : _Palette.dark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: disabled
                    ? null
                    : (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedLocation = v;
                    _applyFilterAndSort();
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeWriteToggle(ColorScheme cs, TextTheme text) {
    final disabled = _writeToggleLoading;
    final on = _repo.isRealtimeWriteEnabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Palette.light.withOpacity(.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note_outlined, size: 16, color: _Palette.base),
          const SizedBox(width: 6),
          Text(
            '삽입:',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            on ? 'ON' : 'OFF',
            style: text.labelMedium?.copyWith(
              color: on ? Colors.teal : cs.outline,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            ),
          ),
          const Spacer(),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: on,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged:
              disabled ? null : (v) => _toggleRealtimeWriteEnabled(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ColorScheme cs) {
    return TextField(
      controller: _searchCtrl,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '번호판 또는 주차 구역으로 검색',
        prefixIcon: Icon(Icons.search, color: _Palette.dark.withOpacity(.7)),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
          icon: Icon(Icons.clear, color: _Palette.dark.withOpacity(.7)),
          onPressed: () {
            _searchCtrl.clear();
            setState(() => _applyFilterAndSort());
          },
        ),
        filled: true,
        fillColor: _Palette.base.withOpacity(.03),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  TextStyle get _headStyle => Theme.of(context).textTheme.labelMedium!.copyWith(
    fontWeight: FontWeight.w800,
    letterSpacing: .2,
    color: _Palette.dark,
  );

  TextStyle get _cellStyle => Theme.of(context).textTheme.bodyMedium!.copyWith(
    height: 1.2,
    color: _Palette.dark.withOpacity(.9),
  );

  TextStyle get _monoStyle => _cellStyle.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
    fontFamilyFallback: const ['monospace'],
  );

  String _fmtDate(DateTime? v) {
    if (v == null) return '';
    final y = v.year.toString().padLeft(4, '0');
    final mo = v.month.toString().padLeft(2, '0');
    final d = v.day.toString().padLeft(2, '0');
    final h = v.hour.toString().padLeft(2, '0');
    final mi = v.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  Widget _buildTable() {
    if (_loading) return const ExpandedLoading();

    if (_rows.isEmpty) {
      if (!_hasFetchedFromServer && _allRows.isEmpty) {
        return const ExpandedEmpty(
          message: '캐시된 데이터가 없습니다.\n하단 탭을 탭하면 해당 데이터가 갱신됩니다.',
        );
      }
      return const ExpandedEmpty(message: '표시할 데이터가 없습니다.');
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _Palette.base.withOpacity(.06),
            border: Border(bottom: BorderSide(color: _Palette.light.withOpacity(.35))),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Plate', style: _headStyle, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Text('Location', style: _headStyle, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: InkWell(
                  onTap: _toggleSortByCreatedAt,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_timeHeaderLabel, style: _headStyle, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _sortOldFirst ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14,
                        color: _Palette.dark.withOpacity(.8),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollCtrl,
            child: ListView.builder(
              controller: _scrollCtrl,
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final r = _rows[i];
                final isEven = i.isEven;
                final rowBg = isEven ? Colors.white : _Palette.base.withOpacity(.02);

                return Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: rowBg,
                    border: Border(
                      bottom: BorderSide(color: _Palette.light.withOpacity(.20), width: .7),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          r.plateNumber,
                          style: _cellStyle.copyWith(fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: Text(
                          r.location,
                          style: _cellStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: Text(
                          _fmtDate(r.createdAt),
                          style: _monoStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.description,
                    style: text.bodySmall?.copyWith(color: cs.outline),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildRowsChip(text)),
                const SizedBox(width: 8),
                Expanded(flex: 5, child: _buildCooldownChip(cs, text)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildRealtimeWriteToggle(cs, text)),
                const SizedBox(width: 8),
                Expanded(flex: 5, child: _buildRealtimeLocationFilter(cs, text)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _buildSearchField(cs),
          ),
          const Divider(height: 1),
          Expanded(child: _buildTable()),
        ],
      ),
    );
  }
}

class ExpandedLoading extends StatelessWidget {
  const ExpandedLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(_Palette.base),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '데이터를 불러오는 중입니다…',
            style: text.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}

class ExpandedEmpty extends StatelessWidget {
  final String message;

  const ExpandedEmpty({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: cs.outline),
            const SizedBox(height: 10),
            Text(
              '기록이 없습니다',
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: _Palette.dark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                color: cs.outline,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
