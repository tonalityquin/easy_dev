import 'package:flutter/material.dart';

class DivisionManagementTab extends StatelessWidget {
  final List<String> divisionList;
  final Future<void> Function(String) onDivisionAdded;
  final Future<void> Function(String) onDivisionDeleted;

  DivisionManagementTab({
    super.key,
    required this.divisionList,
    required this.onDivisionAdded,
    required this.onDivisionDeleted,
  });

  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(labelText: '새 회사 이름 (division)'),
            onSubmitted: onDivisionAdded,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_business),
            label: const Text('회사 추가'),
            onPressed: () => onDivisionAdded(_controller.text),
          ),
          const SizedBox(height: 20),
          const Text('등록된 회사 목록', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: divisionList.length,
              itemBuilder: (context, index) {
                final division = divisionList[index];
                return ListTile(
                  title: Text(division),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => onDivisionDeleted(division),
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
