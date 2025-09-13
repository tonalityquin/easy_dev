// lib/screens/secondary_package/dev_mode_package/area_management_package/status_mapping_helper.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';


// 🔧 전역 리미트 설정값(최소/최대/기본값, prefsKey)을 단일 소스로 관리
import '../../../../utils/plate_limit_config.dart';


/// 지역별(location 단위) 리미트 관리 탭
/// - 상단: Division/Area 선택
/// - 중단: 선택한 Area의 location 목록(= location_limits 문서들)과 개별 리미트 조절 UI
/// - 하단: location 리미트 추가(없는 location 수동 등록)
///
/// 변경점:
/// - 슬라이더를 드래그할 때마다 write 하지 않음.
/// - 값 변경 후 '저장' 버튼을 눌러야 Firestore에 반영됨(쓰기 비용 절감).
///
/// 저장 스키마:
///   collection('location_limits').doc('$area_$location') = {
///     area, location, limit(PlateLimitConfig.min~max), updatedAt
///   }
class StatusMappingHelper extends StatefulWidget {
  const StatusMappingHelper({super.key});


  @override
  State<StatusMappingHelper> createState() => _StatusMappingHelperState();
}


class _StatusMappingHelperState extends State<StatusMappingHelper> {
  // 선택 상태
  String? _selectedDivision;
  String? _selectedArea;


  // 드롭다운 소스
  List<String> _divisions = [];
  List<String> _areas = [];


  // 새 location 추가 입력
  final TextEditingController _newLocCtrl = TextEditingController();
  bool _busy = false;


  // 전역 기본값(표시 목적): SharedPreferences(PlateLimitConfig.prefsKey) [디바이스 단위 기본]
  int _globalDefault = PlateLimitConfig.defaultLimit;


  @override
  void initState() {
    super.initState();
    _loadDivisions();
    _loadGlobalDefault();
  }


  @override
  void dispose() {
    _newLocCtrl.dispose();
    super.dispose();
  }


  Future<void> _loadGlobalDefault() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getInt(PlateLimitConfig.prefsKey) ?? PlateLimitConfig.defaultLimit;
      if (!mounted) return;
      setState(() => _globalDefault = v.clamp(PlateLimitConfig.min, PlateLimitConfig.max));
    } catch (_) {
      // 표시 실패는 무시
    }
  }


  Future<void> _loadDivisions() async {
    final fs = FirebaseFirestore.instance;
    final snap = await fs.collection('divisions').get();
    final list = snap.docs
        .map((d) => (d['name'] as String?)?.trim())
        .whereType<String>()
        .toList()
      ..sort();
    if (!mounted) return;
    setState(() {
      _divisions = list;
      _selectedDivision ??= _divisions.isNotEmpty ? _divisions.first : null;
    });
    await _loadAreas(); // division 선택 후 area 로딩
  }


  Future<void> _loadAreas() async {
    _areas = [];
    _selectedArea = null;
    if (_selectedDivision == null) {
      if (mounted) setState(() {}); // 빈 상태 반영
      return;
    }
    final fs = FirebaseFirestore.instance;
    final snap = await fs
        .collection('areas')
        .where('division', isEqualTo: _selectedDivision)
        .get();
    final list = snap.docs
        .map((d) => (d['name'] as String?)?.trim())
        .whereType<String>()
        .toList()
      ..sort();
    if (!mounted) return;
    setState(() {
      _areas = list;
      _selectedArea = _areas.isNotEmpty ? _areas.first : null;
    });
  }


  /// area + location 필드로 기존 문서 ref를 찾는다. 없으면 null.
  Future<DocumentReference<Map<String, dynamic>>?> _findLimitDocRef(
      String area, String location) async {
    final fs = FirebaseFirestore.instance;
    final qs = await fs
        .collection('location_limits')
        .where('area', isEqualTo: area)
        .where('location', isEqualTo: location)
        .limit(1)
        .get();
    if (qs.docs.isEmpty) return null;
    return qs.docs.first.reference;
  }


  Future<void> _upsertLimit(String area, String location, int limit) async {
    final clamped = limit.clamp(PlateLimitConfig.min, PlateLimitConfig.max);
    final fs = FirebaseFirestore.instance;


    // 1) area+location 조합으로 기존 문서를 찾는다(과거 __, 현재 _ 모두 커버).
    final existRef = await _findLimitDocRef(area, location);
    if (existRef != null) {
      await existRef.set({
        'area': area,
        'location': location,
        'limit': clamped,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }


    // 2) 없으면 새 문서 생성 → 단일 언더스코어 ID 사용
    final newId = '${area}_$location';
    await fs.collection('location_limits').doc(newId).set({
      'area': area,
      'location': location,
      'limit': clamped,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }


  Future<void> _deleteLimit(String area, String location) async {
    final fs = FirebaseFirestore.instance;


    // 1) area+location 조합으로 기존 문서를 찾는다.
    final existRef = await _findLimitDocRef(area, location);
    if (existRef != null) {
      await existRef.delete();
      return;
    }


    // 2) 혹시 남아있을지 모르는 ID 호환 처리(신규/구버전 ID 모두 시도)
    final newId = '${area}_$location';
    final oldId = '${area}__${location}';
    final newRef = fs.collection('location_limits').doc(newId);
    final oldRef = fs.collection('location_limits').doc(oldId);


    final newSnap = await newRef.get();
    if (newSnap.exists) {
      await newRef.delete();
      return;
    }
    final oldSnap = await oldRef.get();
    if (oldSnap.exists) {
      await oldRef.delete();
    }
  }


  @override
  Widget build(BuildContext context) {
    // ✅ 오버플로 방지: isExpanded + ellipsis + isDense
    final divisionDropdown = DropdownButtonFormField<String>(
      value: _selectedDivision,
      isExpanded: true,
      items: _divisions
          .map((e) => DropdownMenuItem(
        value: e,
        child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
      ))
          .toList(),
      selectedItemBuilder: (context) => _divisions
          .map((e) => Align(
        alignment: Alignment.centerLeft,
        child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
      ))
          .toList(),
      onChanged: (v) async {
        setState(() {
          _selectedDivision = v;
          _areas = [];
          _selectedArea = null;
        });
        await _loadAreas();
      },
      decoration: const InputDecoration(
        labelText: '회사(division) 선택',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );


    final areaDropdown = DropdownButtonFormField<String>(
      value: _selectedArea,
      isExpanded: true,
      items: _areas
          .map((e) => DropdownMenuItem(
        value: e,
        child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
      ))
          .toList(),
      selectedItemBuilder: (context) => _areas
          .map((e) => Align(
        alignment: Alignment.centerLeft,
        child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
      ))
          .toList(),
      onChanged: (v) => setState(() => _selectedArea = v),
      decoration: const InputDecoration(
        labelText: '지역(area) 선택',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );


    return AbsorbPointer(
      absorbing: _busy,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 전역 기본값 안내(표시 전용)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '전역 기본 리미트(표시): N = $_globalDefault  (디바이스 기본)\n'
                    '※ 아래에서 설정하는 값은 "선택한 지역의 location별 서버 리미트"입니다. 서버 리미트가 존재하면 전역값 대신 우선 적용됩니다.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const SizedBox(height: 12),


            // 선택 영역
            LayoutBuilder(
              builder: (context, c) {
                // 화면이 좁으면 세로 배치로 자동 전환
                final narrow = c.maxWidth < 360;
                if (narrow) {
                  return Column(
                    children: [
                      divisionDropdown,
                      const SizedBox(height: 12),
                      areaDropdown,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: divisionDropdown),
                    const SizedBox(width: 12),
                    Expanded(child: areaDropdown),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),


            Expanded(
              child: _selectedArea == null
                  ? const Center(child: Text('지역을 선택하세요.'))
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('location_limits')
                    .where('area', isEqualTo: _selectedArea)
                    .orderBy('location')
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('등록된 location 리미트가 없습니다. 아래에서 추가하세요.'),
                    );
                  }
                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final data = docs[i].data();
                      final loc = (data['location'] ?? '').toString();
                      int limit = (data['limit'] ?? _globalDefault) as int;
                      limit = limit.clamp(PlateLimitConfig.min, PlateLimitConfig.max);


                      return _LimitTile(
                        area: _selectedArea!,
                        location: loc,
                        limit: limit,
                        onSave: (v) => _upsertLimit(_selectedArea!, loc, v),
                        onDelete: () => _deleteLimit(_selectedArea!, loc),
                      );
                    },
                  );
                },
              ),
            ),


            const SizedBox(height: 12),
            // 새 location 추가
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newLocCtrl,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: '새 location 이름 입력 (예: B2-01)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) async {
                      if (_selectedArea == null) return;
                      final name = _newLocCtrl.text.trim();
                      if (name.isEmpty) return;
                      setState(() => _busy = true);
                      try {
                        await _upsertLimit(_selectedArea!, name, _globalDefault);
                        _newLocCtrl.clear();
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('추가'),
                  onPressed: _selectedArea == null
                      ? null
                      : () async {
                    final name = _newLocCtrl.text.trim();
                    if (name.isEmpty) return;
                    setState(() => _busy = true);
                    try {
                      await _upsertLimit(_selectedArea!, name, _globalDefault);
                      _newLocCtrl.clear();
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _LimitTile extends StatefulWidget {
  final String area;
  final String location;
  final int limit;
  final ValueChanged<int> onSave; // ✅ 저장 시에만 write
  final VoidCallback onDelete;


  const _LimitTile({
    required this.area,
    required this.location,
    required this.limit,
    required this.onSave,
    required this.onDelete,
  });


  @override
  State<_LimitTile> createState() => _LimitTileState();
}


class _LimitTileState extends State<_LimitTile> {
  late int _value;
  late int _initial;
  bool _saving = false;


  @override
  void initState() {
    super.initState();
    _value = widget.limit.clamp(PlateLimitConfig.min, PlateLimitConfig.max);
    _initial = _value;
  }


  void _onSlider(int v) {
    setState(() => _value = v.clamp(PlateLimitConfig.min, PlateLimitConfig.max));
  }


  Future<void> _onSavePressed() async {
    if (_value == _initial) return;
    setState(() => _saving = true);
    try {
      await Future.sync(() => widget.onSave(_value));
      if (!mounted) return;
      setState(() {
        _initial = _value; // 최신 저장값을 기준값으로 동기화
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('리미트가 저장되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final dirty = _value != _initial;


    return ListTile(
      leading: const Icon(Icons.place, color: Colors.teal),
      title: Text(
        widget.location,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 상태/저장 버튼 행
          Row(
            children: [
              Expanded(
                child: Text(
                  'N = $_value${dirty ? "  (변경됨)" : ""}',
                  style: TextStyle(
                    color: dirty ? Colors.orange[800] : Colors.black87,
                    fontWeight: dirty ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  onPressed: (!dirty || _saving) ? null : _onSavePressed,
                  icon: _saving
                      ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('저장'),
                ),
              ),
            ],
          ),
          // 슬라이더
          Slider(
            value: _value.toDouble(),
            min: PlateLimitConfig.min.toDouble(),
            max: PlateLimitConfig.max.toDouble(),
            divisions: PlateLimitConfig.max - PlateLimitConfig.min,
            label: '$_value',
            onChanged: (v) => _onSlider(v.round()),
          ),
        ],
      ),
      // 삭제 버튼은 trailing에 유지
      trailing: IconButton(
        tooltip: '리미트 삭제(전역 기본 사용)',
        icon: const Icon(Icons.delete_outline),
        onPressed: _saving ? null : widget.onDelete,
      ),
    );
  }
}



