import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/area/area_state.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';

class AreaManagement extends StatefulWidget {
  const AreaManagement({super.key});

  @override
  State<AreaManagement> createState() => _AreaManagementState();
}

class _AreaManagementState extends State<AreaManagement> {
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _divisionController = TextEditingController();

  void _addArea(BuildContext context) {
    final area = _areaController.text.trim();
    final division = _divisionController.text.trim();
    if (area.isEmpty) return;

    context.read<AreaState>().addArea(area, division);
    _areaController.clear();
    _divisionController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final areas = context.watch<AreaState>().availableAreas;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '지역 추가',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _areaController,
              decoration: const InputDecoration(
                labelText: '새 지역 이름',
              ),
              onSubmitted: (_) => _addArea(context),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _divisionController,
              decoration: const InputDecoration(
                labelText: '회사 이름 (division)',
              ),
              onSubmitted: (_) => _addArea(context),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('지역 추가'),
              onPressed: () => _addArea(context),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: areas.length,
                itemBuilder: (context, index) {
                  final area = areas[index];
                  return ListTile(
                    title: Text(area),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        context.read<AreaState>().removeArea(area);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SecondaryMiniNavigation(
        icons: [
          Icons.search,
          Icons.person,
          Icons.sort,
        ],
      ),
    );
  }
}
