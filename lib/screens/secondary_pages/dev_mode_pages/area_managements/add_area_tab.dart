import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddAreaTab extends StatefulWidget {
  final String? selectedDivision;
  final List<String> divisionList;
  final ValueChanged<String?> onDivisionChanged;

  const AddAreaTab({
    super.key,
    required this.selectedDivision,
    required this.divisionList,
    required this.onDivisionChanged,
  });

  @override
  State<AddAreaTab> createState() => _AddAreaTabState();
}

class _AddAreaTabState extends State<AddAreaTab> {
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _englishAreaController = TextEditingController();

  bool _adding = false; // 추가 이중 클릭 방지
  String? _deletingAreaName; // 동시에 하나만 삭제

  Future<List<String>>? _areasFuture; // FutureBuilder 재호출 최소화

  @override
  void initState() {
    super.initState();
    _areasFuture = _loadAreas(); // 초기 캐시
  }

  @override
  void didUpdateWidget(covariant AddAreaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 부모에서 selectedDivision이 바뀐 경우에만 갱신
    if (oldWidget.selectedDivision != widget.selectedDivision) {
      _areasFuture = _loadAreas();
    }
  }

  @override
  void dispose() {
    _areaController.dispose();
    _englishAreaController.dispose();
    super.dispose();
  }

  // 입력 정규화: 선후 공백 제거, '/' → '-', 다중 공백 1개로
  String _norm(String s) =>
      s.trim().replaceAll('/', '-').replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _addArea() async {
    if (_adding) return;

    final rawKr = _areaController.text;
    final areaName = _norm(rawKr);
    final englishAreaName = _englishAreaController.text.trim();
    final division = widget.selectedDivision;

    if (division == null || division.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 회사를 선택하세요.')),
      );
      return;
    }
    if (areaName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 지역 이름(한글)을 입력하세요.')),
      );
      return;
    }

    final areaId = '$division-$areaName';

    setState(() => _adding = true);
    try {
      final fs = FirebaseFirestore.instance;
      final ref = fs.collection('areas').doc(areaId);

      // 중복 생성/경합 방지: 트랜잭션으로 존재 확인 후 생성
      await fs.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) {
          throw Exception('이미 존재하는 지역입니다.');
        }
        tx.set(ref, {
          'name': areaName,
          'englishName': englishAreaName,
          'division': division,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;

      _areaController.clear();
      _englishAreaController.clear();
      FocusScope.of(context).unfocus();

      setState(() {
        _areasFuture = _loadAreas(); // 목록 재로딩 (Future 캐시 갱신)
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ "$areaName" 지역이 추가되었습니다')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 지역 추가 실패: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _adding = false);
    }
  }

  Future<List<String>> _loadAreas() async {
    final division = widget.selectedDivision;
    if (division == null || division.isEmpty) return [];
    final snapshot = await FirebaseFirestore.instance
        .collection('areas')
        .where('division', isEqualTo: division)
        .get(const GetOptions(source: Source.serverAndCache));
    final list = snapshot.docs.map((e) => (e['name'] as String?)?.trim())
        .whereType<String>()
        .toList()
      ..sort((a, b) => a.compareTo(b)); // 정렬 일관성
    return list;
  }

  Future<void> _deleteArea(String areaName) async {
    if (_deletingAreaName != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('다른 삭제 작업이 진행 중입니다. 잠시만 기다려주세요.')),
      );
      return;
    }

    final division = widget.selectedDivision;
    if (division == null || division.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지역 삭제'),
        content: Text('"$areaName" 지역을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deletingAreaName = areaName);
    try {
      final areaId = '$division-$areaName';
      await FirebaseFirestore.instance.collection('areas').doc(areaId).delete();

      if (!mounted) return;
      setState(() {
        _areasFuture = _loadAreas(); // 목록 재로딩 (Future 캐시 갱신)
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🗑️ "$areaName" 지역이 삭제되었습니다')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 삭제 실패: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _deletingAreaName = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _adding || _deletingAreaName != null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: widget.selectedDivision,
            items: widget.divisionList
                .map((div) => DropdownMenuItem(value: div, child: Text(div)))
                .toList(),
            onChanged: busy
                ? null
                : (val) {
              // 부모 콜백 호출 + 로컬 Future 캐시 갱신
              widget.onDivisionChanged(val);
              setState(() {
                _areasFuture = _loadAreas();
              });
            },
            decoration: const InputDecoration(labelText: '회사 선택'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _areaController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: '새 지역 이름(한글)'),
            onSubmitted: (_) => _addArea(),
            enabled: !busy,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _englishAreaController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: '새 지역 이름 (영어)'),
            onSubmitted: (_) => _addArea(),
            enabled: !busy,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: _adding
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add),
            label: Text(_adding ? '추가 중...' : '지역 추가'),
            onPressed: busy ? null : _addArea,
          ),
          const SizedBox(height: 20),
          const Text('해당 회사의 지역 목록', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: widget.selectedDivision == null
                ? const Center(child: Text('📌 회사를 먼저 선택하세요.'))
                : FutureBuilder<List<String>>(
              future: _areasFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final areas = snapshot.data ?? const <String>[];
                if (areas.isEmpty) {
                  return const Center(child: Text('등록된 지역이 없습니다.'));
                }

                return ListView.builder(
                  itemCount: areas.length,
                  itemBuilder: (context, index) {
                    final areaName = areas[index];
                    final deleting = _deletingAreaName == areaName;
                    return ListTile(
                      key: ValueKey(areaName), // 리빌드 안정성
                      title: Text(areaName),
                      trailing: deleting
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : IconButton(
                        tooltip: '지역 삭제',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: busy ? null : () => _deleteArea(areaName),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
