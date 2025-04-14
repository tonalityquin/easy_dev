import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_area_tab.dart';
import 'division_management_tab.dart';
import 'user_account_tab.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';

class AreaManagement extends StatefulWidget {
  const AreaManagement({super.key});

  @override
  State<AreaManagement> createState() => _AreaManagementState();
}

class _AreaManagementState extends State<AreaManagement> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String? _selectedDivision;
  List<String> _divisionList = [];

  String? _accountSelectedDivision;
  String? _accountSelectedArea;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDivisions();
  }

  void _loadDivisions() async {
    final snapshot = await FirebaseFirestore.instance.collection('divisions').get();
    setState(() {
      _divisionList = snapshot.docs.map((e) => e['name'] as String).toList();
      if (_divisionList.isNotEmpty && _selectedDivision == null) {
        _selectedDivision = _divisionList.first;
      }
      if (_divisionList.isNotEmpty && _accountSelectedDivision == null) {
        _accountSelectedDivision = _divisionList.first;
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

    _loadDivisions();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ 회사 "$trimmed" 추가됨')),
    );
  }

  Future<void> _deleteDivision(String name) async {
    try {
      await FirebaseFirestore.instance.collection('divisions').doc(name).delete();
      final areaSnapshot = await FirebaseFirestore.instance
          .collection('areas')
          .where('division', isEqualTo: name)
          .get();
      for (var doc in areaSnapshot.docs) {
        await doc.reference.delete();
      }

      _loadDivisions();

      if (_selectedDivision == name) {
        setState(() {
          _selectedDivision = _divisionList.isNotEmpty ? _divisionList.first : null;
        });
      }
      if (_accountSelectedDivision == name) {
        setState(() {
          _accountSelectedDivision = _divisionList.isNotEmpty ? _divisionList.first : null;
          _accountSelectedArea = null;
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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
              Tab(icon: Icon(Icons.manage_accounts), text: '계정 조회/관리'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            AddAreaTab(
              selectedDivision: _selectedDivision,
              divisionList: _divisionList,
              onDivisionChanged: (val) => setState(() => _selectedDivision = val),
            ),
            DivisionManagementTab(
              divisionList: _divisionList,
              onDivisionAdded: _addDivision,
              onDivisionDeleted: _deleteDivision,
            ),
            UserAccountsTab(
              divisionList: _divisionList,
              selectedDivision: _accountSelectedDivision,
              selectedArea: _accountSelectedArea,
              onDivisionChanged: (val) {
                setState(() {
                  _accountSelectedDivision = val;
                  _accountSelectedArea = null;
                });
              },
              onAreaChanged: (val) => setState(() => _accountSelectedArea = val),
            ),
          ],
        ),
        bottomNavigationBar: const SecondaryMiniNavigation(
          icons: [Icons.search, Icons.person, Icons.sort],
        ),
      ),
    );
  }
}
