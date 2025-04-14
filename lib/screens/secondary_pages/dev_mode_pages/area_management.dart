import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../states/area/area_state.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';

class AreaManagement extends StatefulWidget {
  const AreaManagement({super.key});

  @override
  State<AreaManagement> createState() => _AreaManagementState();
}

class _AreaManagementState extends State<AreaManagement> with SingleTickerProviderStateMixin {
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _newDivisionController = TextEditingController();

  late TabController _tabController;

  String? _selectedDivision;
  List<String> _divisionList = [];

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this);
    _loadDivisions();
    super.initState();
  }

  void _loadDivisions() async {
    final snapshot = await FirebaseFirestore.instance.collection('divisions').get();
    setState(() {
      _divisionList = snapshot.docs.map((e) => e['name'] as String).toList();
      if (_divisionList.isNotEmpty && _selectedDivision == null) {
        _selectedDivision = _divisionList.first;
      }
    });
  }

  Future<void> _addDivision(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    await FirebaseFirestore.instance.collection('divisions').doc(trimmed).set({
      'name': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _newDivisionController.clear();
    _loadDivisions();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ 회사 "$trimmed" 추가됨')),
    );
  }

  Future<void> _deleteDivision(String name) async {
    try {
      await FirebaseFirestore.instance.collection('divisions').doc(name).delete();
      final areaSnapshot =
          await FirebaseFirestore.instance.collection('areas').where('division', isEqualTo: name).get();
      for (var doc in areaSnapshot.docs) {
        await doc.reference.delete();
      }

      _loadDivisions();

      if (_selectedDivision == name) {
        setState(() {
          _selectedDivision = _divisionList.isNotEmpty ? _divisionList.first : null;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🗑️ "$name" 회사 및 소속 지역 삭제됨')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 삭제 실패: $e')),
      );
    }
  }

  void _addArea(BuildContext context) {
    final area = _areaController.text.trim();
    final division = _selectedDivision ?? '';
    if (area.isEmpty || division.isEmpty) return;

    context.read<AreaState>().addArea(area, division);
    _areaController.clear();
  }

  Widget _buildAreaTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: _selectedDivision,
            items: _divisionList.map((div) => DropdownMenuItem(value: div, child: Text(div))).toList(),
            onChanged: (val) => setState(() => _selectedDivision = val),
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
            child: _selectedDivision == null
                ? const Center(
                    child: Text('📌 회사를 먼저 선택하세요.', style: TextStyle(fontSize: 16)),
                  )
                : FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('areas')
                        .where('division', isEqualTo: _selectedDivision)
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

  Widget _buildDivisionTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _newDivisionController,
            decoration: const InputDecoration(labelText: '새 회사 이름 (division)'),
            onSubmitted: _addDivision,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_business),
            label: const Text('회사 추가'),
            onPressed: () => _addDivision(_newDivisionController.text),
          ),
          const SizedBox(height: 20),
          const Text('등록된 회사 목록', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: _divisionList.length,
              itemBuilder: (context, index) {
                final division = _divisionList[index];
                return ListTile(
                  title: Text(division),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => _deleteDivision(division),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black87,
          title: const Text('지역 및 회사 관리', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.location_city), text: '지역 추가'),
              Tab(icon: Icon(Icons.business), text: '회사 관리'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildAreaTab(context),
            _buildDivisionTab(),
          ],
        ),
        bottomNavigationBar: const SecondaryMiniNavigation(
          icons: [
            Icons.search,
            Icons.person,
            Icons.sort,
          ],
        ),
      ),
    );
  }
}
