import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DivisionManagementTab extends StatefulWidget {
  final List<String> divisionList;
  final Future<void> Function(String) onDivisionAdded;
  final Future<void> Function(String) onDivisionDeleted;

  const DivisionManagementTab({
    super.key,
    required this.divisionList,
    required this.onDivisionAdded,
    required this.onDivisionDeleted,
  });

  @override
  State<DivisionManagementTab> createState() => _DivisionManagementTabState();
}

class _DivisionManagementTabState extends State<DivisionManagementTab> {
  final TextEditingController _controller = TextEditingController();

  Future<void> _handleAddDivision() async {
    final input = _controller.text.trim();

    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회사 이름을 입력해주세요.')),
      );
      return;
    }

    await widget.onDivisionAdded(input);

    final areaId = '$input-$input';
    await FirebaseFirestore.instance.collection('areas').doc(areaId).set({
      'name': input,
      'division': input,
      'isHeadquarter': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    setState(() {
      _controller.clear();
    });

    FocusScope.of(context).unfocus();
    debugPrint("✅ Division 추가 후 UI 갱신됨: $input");
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(labelText: '새 회사 이름 (division)'),
            onSubmitted: (_) => _handleAddDivision(),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_business),
            label: const Text('회사 추가'),
            onPressed: _handleAddDivision,
          ),
          const SizedBox(height: 20),
          const Text('등록된 회사 목록', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: widget.divisionList.length,
              itemBuilder: (context, index) {
                final division = widget.divisionList[index];
                return ListTile(
                  title: Text(division),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () async {
                      await widget.onDivisionDeleted(division);
                      final areaId = '$division-$division';
                      await FirebaseFirestore.instance.collection('areas').doc(areaId).delete();
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

