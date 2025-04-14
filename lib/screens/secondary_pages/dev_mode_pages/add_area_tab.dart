import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../../states/area/area_state.dart';

class AddAreaTab extends StatelessWidget {
  final String? selectedDivision;
  final List<String> divisionList;
  final ValueChanged<String?> onDivisionChanged;

  AddAreaTab({
    super.key,
    required this.selectedDivision,
    required this.divisionList,
    required this.onDivisionChanged,
  });

  final TextEditingController _areaController = TextEditingController();

  void _addArea(BuildContext context) {
    final area = _areaController.text.trim();
    final division = selectedDivision ?? '';
    if (area.isEmpty || division.isEmpty) return;

    context.read<AreaState>().addArea(area, division);
    _areaController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: selectedDivision,
            items: divisionList
                .map((div) => DropdownMenuItem(value: div, child: Text(div)))
                .toList(),
            onChanged: onDivisionChanged,
            decoration: const InputDecoration(labelText: '회사 선택'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _areaController,
            decoration: const InputDecoration(labelText: '새 지역 이름'),
            onSubmitted: (_) => _addArea(context),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('지역 추가'),
            onPressed: () => _addArea(context),
          ),
          const SizedBox(height: 20),
          const Text('해당 회사의 지역 목록', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: selectedDivision == null
                ? const Center(child: Text('📌 회사를 먼저 선택하세요.'))
                : FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('areas')
                  .where('division', isEqualTo: selectedDivision)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('등록된 지역이 없습니다.'));
                }

                final docs = snapshot.data!.docs;
                return ListView(
                  children: docs.map((doc) {
                    final areaName = doc['name'];
                    return ListTile(
                      title: Text(areaName),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          context.read<AreaState>().removeArea(areaName);
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
