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

  Future<void> _addArea() async {
    final areaName = _areaController.text.trim();
    final division = widget.selectedDivision;
    if (areaName.isEmpty || division == null || division.isEmpty) return;

    final areaId = '$division-$areaName';
    final areaDoc = FirebaseFirestore.instance.collection('areas').doc(areaId);

    await areaDoc.set({
      'name': areaName,
      'division': division,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _areaController.clear();
    FocusScope.of(context).unfocus();
    setState(() {}); // 🔄 FutureBuilder 리빌드

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ "$areaName" 지역이 추가되었습니다')),
    );
  }

  Future<List<String>> _loadAreas() async {
    if (widget.selectedDivision == null) return [];
    final snapshot = await FirebaseFirestore.instance
        .collection('areas')
        .where('division', isEqualTo: widget.selectedDivision)
        .get();
    return snapshot.docs.map((e) => e['name'] as String).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: widget.selectedDivision,
            items: widget.divisionList
                .map((div) => DropdownMenuItem(value: div, child: Text(div)))
                .toList(),
            onChanged: widget.onDivisionChanged,
            decoration: const InputDecoration(labelText: '회사 선택'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _areaController,
            decoration: const InputDecoration(labelText: '새 지역 이름'),
            onSubmitted: (_) => _addArea(),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('지역 추가'),
            onPressed: _addArea,
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
                if (areas.isEmpty) return const Center(child: Text('등록된 지역이 없습니다.'));

                return ListView(
                  children: areas.map((areaName) {
                    return ListTile(
                      title: Text(areaName),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final areaId = '${widget.selectedDivision}-$areaName';
                          await FirebaseFirestore.instance.collection('areas').doc(areaId).delete();
                          setState(() {});
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
