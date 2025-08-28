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

  bool _adding = false;                 // 추가 이중 클릭 방지
  String? _deletingAreaName;            // 동시에 하나만 삭제

  @override
  void dispose() {
    _areaController.dispose();
    _englishAreaController.dispose();
    super.dispose();
  }

  Future<void> _addArea() async {
    if (_adding) return;

    final areaName = _areaController.text.trim();
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
    // Firestore 문서 ID에는 '/' 불가
    if (areaName.contains('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지역 이름에 "/" 문자는 사용할 수 없습니다.')),
      );
      return;
    }

    final areaId = '$division-$areaName';

    setState(() => _adding = true);
    try {
      final areaDoc = FirebaseFirestore.instance.collection('areas').doc(areaId);
      await areaDoc.set({
        'name': areaName,
        'englishName': englishAreaName,
        'division': division,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _areaController.clear();
      _englishAreaController.clear();
      FocusScope.of(context).unfocus();
      setState(() {}); // 목록 갱신 트리거

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
    if (widget.selectedDivision == null) return [];
    final snapshot = await FirebaseFirestore.instance
        .collection('areas')
        .where('division', isEqualTo: widget.selectedDivision)
        .get();
    return snapshot.docs.map((e) => e['name'] as String).toList();
  }

  Future<void> _deleteArea(String areaName) async {
    if (_deletingAreaName != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('다른 삭제 작업이 진행 중입니다. 잠시만 기다려주세요.')),
      );
      return;
    }

    final division = widget.selectedDivision;
    if (division == null) return;

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
      setState(() {}); // 목록 갱신 트리거

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
            onChanged: busy ? null : widget.onDivisionChanged,
            decoration: const InputDecoration(labelText: '회사 선택'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _areaController,
            decoration: const InputDecoration(labelText: '새 지역 이름(한글)'),
            onSubmitted: (_) => _addArea(),
            enabled: !busy,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _englishAreaController,
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
              future: _loadAreas(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final areas = snapshot.data ?? [];
                if (areas.isEmpty) {
                  return const Center(child: Text('등록된 지역이 없습니다.'));
                }

                return ListView.builder(
                  itemCount: areas.length,
                  itemBuilder: (context, index) {
                    final areaName = areas[index];
                    final deleting = _deletingAreaName == areaName;
                    return ListTile(
                      title: Text(areaName),
                      trailing: deleting
                          ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
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
