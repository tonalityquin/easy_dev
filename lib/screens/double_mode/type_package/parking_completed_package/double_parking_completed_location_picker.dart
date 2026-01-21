import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/plate_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/location/location_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/block_dialogs/blocking_dialog.dart'; // runWithBlockingDialog
import '../../../../utils/block_dialogs/duration_blocking_dialog.dart'; // showDurationBlockingDialog ✅
import '../../../../utils/init/date_utils.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../widgets/container/plate_container_fee_calculator.dart';
import '../../../../widgets/container/plate_custom_box.dart';
import '../../../../widgets/dialog/billing_bottom_sheet/fee_calculator.dart';

import '../../../hubs_mode/dev_package/debug_package/debug_action_recorder.dart';
import 'widgets/double_parking_completed_status_bottom_sheet.dart';


const String _kLocationAll = '전체';

/// ✅ (분리) 입차 완료 "실시간(view) 모드" 진입 게이트(ON/OFF)
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

/// Deep Blue 팔레트(기존 컨셉 유지)
class _Palette {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

/// UI 렌더링 Row VM
/// ✅ 변경: view items key(=plateDocId)를 보관하여
///         row 탭 시 원본 plates/{plateDocId} 단건 조회가 가능하도록 확장.
class _RowVM {
  final String plateId; // ✅ plates 문서 docId (예: 12가3456_서울A)
  final String plateNumber;
  final String location;
  final DateTime? createdAt;

  const _RowVM({
    required this.plateId,
    required this.plateNumber,
    required this.location,
    required this.createdAt,
  });
}

/// ─────────────────────────────────────────────────────────
/// refresh 컨트롤러(탭 탭/헤더 등 외부 이벤트에서 안전하게 refresh 트리거)
/// ─────────────────────────────────────────────────────────
class _RealtimeController {
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
/// 제너릭 view repository (입차 완료(view) 전용)
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
        final plateDocId = entry.key?.toString() ?? ''; // ✅ view item key
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
            plateId: plateDocId, // ✅ 추가
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

/// ✅ (임베드 버전) 더블 모드: 입차 요청/출차 요청 없음
/// - “입차 완료(view)” 단일 화면이지만,
///   하단에 '입차 완료' 탭을 포함하고 탭을 누르면(재탭 포함) 동일 갱신 로직 수행.
/// - 내부 Scaffold 제거 → 외부 ControlButtons가 계속 보이고, body 영역까지만 자연스럽게 채움.
class DoubleParkingCompletedLocationPicker extends StatefulWidget {
  final VoidCallback? onClose;

  const DoubleParkingCompletedLocationPicker({
    super.key,
    this.onClose,
  });

  @override
  State<DoubleParkingCompletedLocationPicker> createState() =>
      _DoubleParkingCompletedLocationPickerState();
}

class _DoubleParkingCompletedLocationPickerState
    extends State<DoubleParkingCompletedLocationPicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _pcGate = false;
  bool _gatesLoaded = false;

  final _RealtimeController _ctrl = _RealtimeController();

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  String get _area {
    final userArea = context.read<UserState>().currentArea.trim();
    final stateArea = context.read<AreaState>().currentArea.trim();
    return userArea.isNotEmpty ? userArea : stateArea;
  }

  @override
  void initState() {
    super.initState();

    // ✅ 단일 탭(입차 완료)이라도 TabBar 구성 유지
    _tabCtrl = TabController(length: 1, vsync: this);
    _tabCtrl.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    _loadGate();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGate() async {
    try {
      final pc = await ParkingCompletedRealtimeTabGate.isEnabled();
      if (!mounted) return;
      setState(() {
        _pcGate = pc;
        _gatesLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pcGate = false;
        _gatesLoaded = true;
      });
    }
  }

  // ✅ 탭을 누르면(재탭 포함) 갱신: 기존 패턴과 동일하게 _ctrl.refreshUser() 호출
  void _requestRefreshByTabTap() {
    _trace(
      '입차 완료 탭 탭(갱신)',
      meta: <String, dynamic>{
        'screen': 'double_parking_completed_view_embedded',
        'action': 'tab_tap_refresh',
        'area': _area,
        'gatesLoaded': _gatesLoaded,
        'gateEnabled': _pcGate,
        'ctrlBound': _ctrl.isBound,
      },
    );

    if (!_gatesLoaded) {
      showSelectedSnackbar(context, '설정 확인 중입니다.');
      return;
    }

    if (!_pcGate) {
      HapticFeedback.selectionClick();
      showSelectedSnackbar(
        context,
        '입차 완료 실시간 모드가 비활성화되어 있습니다. 설정에서 ON 후 사용해 주세요.',
      );
      return;
    }

    // TabBarView가 아직 body를 만들기 전일 수 있어 post-frame + 딜레이 재시도 패턴 유지
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (_ctrl.isBound) {
        await _ctrl.refreshUser();
        return;
      }

      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await _ctrl.refreshUser();
    });
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
            child: Icon(Icons.table_chart_outlined, color: _Palette.base, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '입차 완료 테이블',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _Palette.dark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '지역: $_area',
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
            onPressed: () {
              final cb = widget.onClose;
              if (cb != null) {
                cb();
                return;
              }
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  // ✅ 하단 바: 탭(1개) 존재. 탭 탭 시 갱신.
  Widget _buildBottomTabBar(ColorScheme cs) {
    return Container(
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
          onTap: (_) {
            // ✅ 단일 탭이지만 탭을 "누르면" 갱신되는 UX 유지
            _requestRefreshByTabTap();
          },
          labelColor: _Palette.base,
          unselectedLabelColor: cs.outline,
          indicatorColor: _Palette.base,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          tabs: [
            Tab(child: _tabLabel(text: '입차 완료', enabled: _pcGate)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildTopHeader(textTheme, cs),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              physics: const PageScrollPhysics(),
              children: [
                _pcGate
                    ? _UnifiedTableBody(
                  controller: _ctrl,
                  description:
                  '하단 “입차 완료” 탭을 누르면 데이터가 갱신됩니다. 잦은 갱신은 앱에 무리를 줍니다.',
                )
                    : const _LockedPanel(
                  title: '입차 완료 실시간 모드가 비활성화되어 있습니다',
                  message:
                  '설정에서 “입차 완료 실시간 모드(탭) 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
                ),
              ],
            ),
          ),
          // ✅ 외부 ControlButtons 바로 위에 위치
          _buildBottomTabBar(cs),
        ],
      ),
    );
  }
}

class _LockedPanel extends StatelessWidget {
  final String title;
  final String message;

  const _LockedPanel({
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
/// 입차 완료(view) 단일 테이블 본문
/// ─────────────────────────────────────────────────────────
class _UnifiedTableBody extends StatefulWidget {
  final _RealtimeController controller;
  final String description;

  const _UnifiedTableBody({
    required this.controller,
    required this.description,
  });

  @override
  State<_UnifiedTableBody> createState() => _UnifiedTableBodyState();
}

class _UnifiedTableBodyState extends State<_UnifiedTableBody>
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

  // ✅ 하이브리드 상세 조회 캐시/인플라이트
  final Map<String, PlateModel> _plateDetailCache = <String, PlateModel>{};
  final Map<String, Future<PlateModel?>> _plateDetailInflight =
  <String, Future<PlateModel?>>{};

  // ✅ 상세 오픈 중복 방지
  bool _openingDetail = false;

  String get _primaryTimeField => 'parkingCompletedAt';
  String get _timeHeaderLabel => 'Entry';
  String get _collection => 'parking_completed_view';
  String get _prefsKeyWriteEnabled =>
      'parking_completed_realtime_write_enabled_v1';

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

    // ✅ 하단 탭 탭(refresh)이 호출할 바인딩
    widget.controller._bindRefresh(_refreshFromUser);

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

  // ✅ 하단 탭 탭이 호출하는 “동일 갱신 로직”
  Future<void> _refreshFromUser() async {
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

  // ✅ 하이브리드: 원본 plates/{plateId} 단건 조회(캐시/인플라이트 포함)
  Future<PlateModel?> _fetchPlateDetail(String plateId) async {
    final id = plateId.trim();
    if (id.isEmpty) return null;

    final cached = _plateDetailCache[id];
    if (cached != null) return cached;

    final inflight = _plateDetailInflight[id];
    if (inflight != null) return inflight;

    final fut = () async {
      try {
        final doc =
        await FirebaseFirestore.instance.collection('plates').doc(id).get();

        if (!doc.exists) return null;

        final plate = PlateModel.fromDocument(doc);
        _plateDetailCache[id] = plate;
        return plate;
      } catch (_) {
        return null;
      } finally {
        _plateDetailInflight.remove(id);
      }
    }();

    _plateDetailInflight[id] = fut;
    return fut;
  }

  String _formatElapsed(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours시간 $minutes분';
    } else if (minutes > 0) {
      return '$minutes분 $seconds초';
    } else {
      return '$seconds초';
    }
  }

  FeeMode _parseFeeMode(String? modeString) {
    switch (modeString) {
      case 'plus':
        return FeeMode.plus;
      case 'minus':
        return FeeMode.minus;
      default:
        return FeeMode.normal;
    }
  }

  String _fmtDate(DateTime? v) {
    if (v == null) return '';
    final y = v.year.toString().padLeft(4, '0');
    final mo = v.month.toString().padLeft(2, '0');
    final d = v.day.toString().padLeft(2, '0');
    final h = v.hour.toString().padLeft(2, '0');
    final mi = v.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  /// ✅ 리팩터링 핵심(요구사항 반영):
  /// - Row 탭 시 "5초 취소 가능" showDurationBlockingDialog를 먼저 실행
  /// - 사용자가 취소하면 plates 조회(=비용) 자체를 발생시키지 않음
  /// - 취소하지 않으면 runWithBlockingDialog로 원본 단건 조회 후 상세 dialog 표시
  /// - ✅ 추가: 상세 dialog 하단에 "작업 수행" 버튼 → 닫힌 뒤 status bottom sheet 오픈
  Future<void> _openHybridDetailPopup(_RowVM r) async {
    if (_openingDetail) return;
    _openingDetail = true;

    try {
      final plateId = r.plateId.trim();
      if (plateId.isEmpty) {
        showFailedSnackbar(context, '상세 조회 식별자(plateId)가 비어 있습니다.');
        return;
      }

      _trace(
        '입차 완료 실시간 테이블 행 탭(확인 대기 다이얼로그)',
        meta: <String, dynamic>{
          'screen': 'double_parking_completed_view_embedded',
          'action': 'row_tap_open_duration_blocking_dialog',
          'area': _currentArea,
          'plateId': plateId,
          'plateNumber': r.plateNumber,
          'location': r.location,
          'viewTime': _fmtDate(r.createdAt),
        },
      );

      // ✅ 0) 5초 취소 가능 다이얼로그(사용자 의도 확인)
      final proceed = await showDurationBlockingDialog(
        context,
        message: '원본 데이터를 불러옵니다.\n(취소하면 조회 비용이 발생하지 않습니다)',
        duration: const Duration(seconds: 5),
      );

      if (!mounted) return;

      if (!proceed) {
        _trace(
          '원본 조회 취소(사용자)',
          meta: <String, dynamic>{
            'screen': 'double_parking_completed_view_embedded',
            'action': 'duration_blocking_dialog_cancel',
            'area': _currentArea,
            'plateId': plateId,
          },
        );
        showSelectedSnackbar(context, '취소했습니다. 원본 조회를 실행하지 않습니다.');
        return;
      }

      _trace(
        '원본 조회 진행(자동/사용자)',
        meta: <String, dynamic>{
          'screen': 'double_parking_completed_view_embedded',
          'action': 'duration_blocking_dialog_proceed',
          'area': _currentArea,
          'plateId': plateId,
        },
      );

      // ✅ 1) 원본 단건 조회(plates/{id}.get)를 별도 로딩 다이얼로그로 수행
      final plate = await runWithBlockingDialog<PlateModel?>(
        context: context,
        message: '원본 데이터를 불러오는 중입니다...',
        task: () => _fetchPlateDetail(plateId),
      );

      if (!mounted) return;

      // ✅ 2) 로딩 다이얼로그가 닫힌 뒤, 상세 다이얼로그 표시
      if (plate == null) {
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (_) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Material(
                  color: Colors.transparent,
                  child: AlertDialog(
                    backgroundColor: Colors.white,
                    elevation: 8,
                    insetPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    content: _PlateDetailNotFoundDialog(
                      plateId: plateId,
                      viewPlateNumber: r.plateNumber,
                      viewLocation: r.location,
                      viewTimeText: _fmtDate(r.createdAt),
                    ),
                  ),
                ),
              ),
            );
          },
        );
        return;
      }

      // ✅ 상세 표시: 서비스모드 PlateCustomBox 수준의 정보 재구성
      final billType = billTypeFromString(plate.billingType);
      final bool isRegular = billType == BillType.fixed;

      final int basicStandard = plate.basicStandard ?? 0;
      final int basicAmount = plate.basicAmount ?? 0;
      final int addStandard = plate.addStandard ?? 0;
      final int addAmount = plate.addAmount ?? 0;

      int currentFee = 0;
      if (!isRegular) {
        if (plate.isLockedFee && plate.lockedFeeAmount != null) {
          currentFee = plate.lockedFeeAmount!;
        } else {
          currentFee = calculateParkingFee(
            entryTimeInSeconds: plate.requestTime.millisecondsSinceEpoch ~/ 1000,
            currentTimeInSeconds:
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            basicStandard: basicStandard,
            basicAmount: basicAmount,
            addStandard: addStandard,
            addAmount: addAmount,
            isLockedFee: plate.isLockedFee,
            lockedAtTimeInSeconds: plate.lockedAtTimeInSeconds,
            userAdjustment: plate.userAdjustment ?? 0,
            mode: _parseFeeMode(plate.feeMode),
          ).toInt();
        }
      }

      final feeText = isRegular
          ? '${plate.isLockedFee ? (plate.lockedFeeAmount ?? 0) : (plate.regularAmount ?? 0)}원'
          : '$currentFee원';

      final DateTime endForElapsed = DateTime.now();
      final elapsedText =
      _formatElapsed(endForElapsed.difference(plate.requestTime));

      final backgroundColor =
      ((plate.billingType?.trim().isNotEmpty ?? false) && plate.isLockedFee)
          ? Colors.orange[50]
          : Colors.white;

      final bool isSelected = plate.isSelected;
      final String displayUser =
      isSelected ? (plate.selectedBy ?? '') : plate.userName;

      // ✅ 변경: showDialog<bool>로 결과를 받아 작업 수행 여부를 판단
      final bool? doWork = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: Colors.transparent,
                child: AlertDialog(
                  backgroundColor: Colors.white,
                  elevation: 8,
                  insetPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  content: _PlateDetailBodyDialog(
                    title: '번호판 상세',
                    subtitle: 'VIEW: ${r.location} / ${_fmtDate(r.createdAt)}   ·   '
                        'PLATES: ${plate.location} / ${CustomDateUtils.formatTimestamp(plate.requestTime)}',
                    child: PlateCustomBox(
                      topLeftText: '소속',
                      topCenterText:
                      '${plate.region ?? '전국'} ${plate.plateNumber}',
                      topRightUpText: plate.billingType ?? '없음',
                      topRightDownText: feeText,
                      midLeftText: plate.location,
                      midCenterText: displayUser.isEmpty ? '-' : displayUser,
                      midRightText:
                      CustomDateUtils.formatTimeForUI(plate.requestTime),
                      bottomLeftLeftText: plate.statusList.isNotEmpty
                          ? plate.statusList.join(", ")
                          : "",
                      bottomLeftCenterText: plate.customStatus ?? '',
                      bottomRightText: elapsedText,
                      isSelected: isSelected,
                      backgroundColor: backgroundColor,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    showWorkButton: true,
                    workButtonText: '작업 수행',
                  ),
                ),
              ),
            ),
          );
        },
      );

      if (!mounted) return;

      // ✅ 작업 수행 선택 시: 다이얼로그 닫힌 뒤 bottom sheet 오픈
      if (doWork == true) {
        final rootCtx = Navigator.of(context, rootNavigator: true).context;

        _trace(
          '상세 다이얼로그 작업 수행 버튼 클릭(상태 시트 오픈)',
          meta: <String, dynamic>{
            'screen': 'double_parking_completed_view_embedded',
            'action': 'detail_dialog_open_status_bottom_sheet',
            'area': _currentArea,
            'plateId': plate.id,
            'plateNumber': plate.plateNumber,
          },
        );

        await showDoubleParkingCompletedStatusBottomSheetFromDialog(
          context: rootCtx,
          plate: plate,
        );
      }
    } finally {
      _openingDetail = false;
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
              onChanged: disabled ? null : (v) => _toggleRealtimeWriteEnabled(v),
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
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

  Widget _buildTable() {
    if (_loading) return const _ExpandedLoading();

    if (_rows.isEmpty) {
      if (!_hasFetchedFromServer && _allRows.isEmpty) {
        return const _ExpandedEmpty(
          message: '캐시된 데이터가 없습니다.\n하단 “입차 완료” 탭을 누르면 데이터가 갱신됩니다.',
        );
      }
      return const _ExpandedEmpty(message: '표시할 데이터가 없습니다.');
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _Palette.base.withOpacity(.06),
            border: Border(
              bottom: BorderSide(color: _Palette.light.withOpacity(.35)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Plate',
                    style: _headStyle, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Text('Location',
                    style: _headStyle, overflow: TextOverflow.ellipsis),
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
                        child: Text(_timeHeaderLabel,
                            style: _headStyle,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _sortOldFirst
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
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
                final rowBg =
                isEven ? Colors.white : _Palette.base.withOpacity(.02);

                // ✅ Row 탭 → showDurationBlockingDialog → (진행 시) 원본 로딩 후 상세 dialog
                return Material(
                  color: rowBg,
                  child: InkWell(
                    onTap: () async => _openHybridDetailPopup(r),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _Palette.light.withOpacity(.20),
                            width: .7,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              r.plateNumber,
                              style: _cellStyle.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
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
                    ),
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

class _ExpandedLoading extends StatelessWidget {
  const _ExpandedLoading();

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

class _ExpandedEmpty extends StatelessWidget {
  final String message;

  const _ExpandedEmpty({required this.message});

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

/// ─────────────────────────────────────────────────────────
/// 하이브리드 상세 팝업(Dialog) UI
/// ─────────────────────────────────────────────────────────

class _PlateDetailNotFoundDialog extends StatelessWidget {
  final String plateId;
  final String viewPlateNumber;
  final String viewLocation;
  final String viewTimeText;

  const _PlateDetailNotFoundDialog({
    required this.plateId,
    required this.viewPlateNumber,
    required this.viewLocation,
    required this.viewTimeText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '번호판 상세',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _Palette.dark,
                  ),
                ),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '원본 plates 문서를 찾을 수 없습니다.',
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text('plateId: $plateId',
                    style: text.bodySmall?.copyWith(color: cs.outline)),
                const SizedBox(height: 6),
                Text('VIEW Plate: $viewPlateNumber',
                    style: text.bodySmall?.copyWith(color: cs.outline)),
                Text('VIEW Location: $viewLocation',
                    style: text.bodySmall?.copyWith(color: cs.outline)),
                Text('VIEW Time: $viewTimeText',
                    style: text.bodySmall?.copyWith(color: cs.outline)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PlateDetailBodyDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  // ✅ 추가
  final bool showWorkButton;
  final String workButtonText;

  const _PlateDetailBodyDialog({
    required this.title,
    required this.subtitle,
    required this.child,
    this.showWorkButton = false,
    this.workButtonText = '작업 수행',
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _Palette.dark,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  // ✅ 변경: 작업 수행과 구분하기 위해 false 반환(또는 null)
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                subtitle,
                style: text.bodySmall?.copyWith(color: cs.outline),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            child,
            const SizedBox(height: 8),

            // ✅ 추가: 하단 "작업 수행" 버튼
            if (showWorkButton) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    // ✅ showDialog<bool> 결과로 true 반환
                    Navigator.of(context).pop(true);
                  },
                  icon: const Icon(Icons.playlist_add_check),
                  label: Text(
                    workButtonText,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _Palette.base,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
            ],
          ],
        ),
      ),
    );
  }
}
