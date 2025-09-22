import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../utils/snackbar_helper.dart';
import 'area_management_package/add_area_tab.dart';
import 'area_management_package/division_management_tab.dart';
import 'area_management_package/user_account_tab.dart';
import 'area_management_package/status_mapping_helper.dart';

// ✅ UsageReporter 계측
import '../../../utils/usage_reporter.dart';

class AreaManagement extends StatefulWidget {
  const AreaManagement({super.key});

  @override
  State<AreaManagement> createState() => _AreaManagementState();
}

class _AreaManagementState extends State<AreaManagement> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String? _selectedDivision;
  List<String> _divisionList = [];

  String? _accountSelectedDivision;
  String? _accountSelectedArea;

  // ✅ 동시에 하나만 삭제: 진행 상태 플래그/대상명
  bool _isDeletingDivision = false;
  String? _deletingDivisionName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadDivisions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDivisions() async {
    try {
      final fs = FirebaseFirestore.instance;
      final snap = await fs.collection('divisions').get();

      // ✅ 계측: divisions read
      try {
        await UsageReporter.instance.report(
          area: 'divisions',
          action: 'read',
          n: snap.docs.length,
          source: 'AreaManagement._loadDivisions.divisions.get',
        );
      } catch (_) {}

      final divisions = snap.docs.map((e) => (e['name'] as String?)?.trim()).whereType<String>().toList()..sort();

      if (!mounted) return;
      setState(() {
        _divisionList = divisions;

        // 지역 추가 탭용 선택값 보정
        if (_selectedDivision != null && !_divisionList.contains(_selectedDivision)) {
          _selectedDivision = _divisionList.isNotEmpty ? _divisionList.first : null;
        } else {
          _selectedDivision ??= _divisionList.isNotEmpty ? _divisionList.first : null;
        }

        // 계정 탭용 선택값 보정
        if (_accountSelectedDivision != null && !_divisionList.contains(_accountSelectedDivision)) {
          _accountSelectedDivision = _divisionList.isNotEmpty ? _divisionList.first : null;
          _accountSelectedArea = null;
        } else {
          _accountSelectedDivision ??= _divisionList.isNotEmpty ? _divisionList.first : null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '회사 목록 로드 실패: $e');
    }
  }

  Future<void> _addDivision(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('divisions').doc(trimmed).set({
        'name': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ✅ 계측: divisions write 1
      try {
        await UsageReporter.instance.report(
          area: trimmed,
          action: 'write',
          n: 1,
          source: 'AreaManagement._addDivision.divisions.set',
        );
      } catch (_) {}

      await _loadDivisions();

      if (!mounted) return;
      showSuccessSnackbar(context, '✅ 회사 "$trimmed" 추가됨');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '❌ 추가 실패: $e');
    }
  }

  Future<void> _deleteDivision(String name) async {
    // ✅ 동시 재진입 차단: 이미 삭제 중이면 즉시 반환
    if (_isDeletingDivision) {
      if (!mounted) return;
      showSelectedSnackbar(context, '다른 삭제 작업이 진행 중입니다. 잠시만 기다려주세요.');
      return;
    }

    setState(() {
      _isDeletingDivision = true;
      _deletingDivisionName = name;
    });

    try {
      final fs = FirebaseFirestore.instance;
      final divRef = fs.collection('divisions').doc(name);
      final areasSnap = await fs.collection('areas').where('division', isEqualTo: name).get();

      // ✅ 계측: areas read for cascade
      try {
        await UsageReporter.instance.report(
          area: name,
          action: 'read',
          n: areasSnap.docs.length,
          source: 'AreaManagement._deleteDivision.areas.queryForCascade',
        );
      } catch (_) {}

      // 대량 삭제 원자성/성능: WriteBatch로 청크 커밋
      WriteBatch batch = fs.batch();
      int ops = 0;

      batch.delete(divRef);
      ops++;

      for (final doc in areasSnap.docs) {
        batch.delete(doc.reference);
        ops++;
        if (ops >= 450) {
          await batch.commit();
          // ✅ 계측: 중간 커밋 delete ops
          try {
            await UsageReporter.instance.report(
              area: name,
              action: 'delete',
              n: ops,
              source: 'AreaManagement._deleteDivision.batch.commit.partial',
            );
          } catch (_) {}
          batch = fs.batch();
          ops = 0;
        }
      }
      if (ops > 0) {
        await batch.commit();
        // ✅ 계측: 마지막 커밋 delete ops
        try {
          await UsageReporter.instance.report(
            area: name,
            action: 'delete',
            n: ops,
            source: 'AreaManagement._deleteDivision.batch.commit.final',
          );
        } catch (_) {}
      }

      await _loadDivisions();

      if (!mounted) return;
      setState(() {
        if (_selectedDivision == name) {
          _selectedDivision = _divisionList.isNotEmpty ? _divisionList.first : null;
        }
        if (_accountSelectedDivision == name) {
          _accountSelectedDivision = _divisionList.isNotEmpty ? _divisionList.first : null;
          _accountSelectedArea = null;
        }
      });

      showSuccessSnackbar(context, '🗑️ "$name" 회사 및 소속 지역 삭제됨');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '❌ 삭제 실패: $e');
    } finally {
      // ⛔️ return 금지: mounted만 체크하고 상태만 정리
      if (mounted) {
        setState(() {
          _isDeletingDivision = false;
          _deletingDivisionName = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 직접 생성한 TabController 사용
    final body = TabBarView(
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
          onDivisionDeleted: _deleteDivision, // 삭제는 부모에서 직렬화
        ),
        UserAccountsTab(
          selectedDivision: _accountSelectedDivision,
          selectedArea: _accountSelectedArea,
          onDivisionChanged: (val) {
            setState(() {
              _accountSelectedDivision = val;
              _accountSelectedArea = null; // 회사 바꾸면 지역 초기화
            });
          },
          onAreaChanged: (val) => setState(() => _accountSelectedArea = val),
        ),
        const StatusMappingHelper(),
      ],
    );

    // ✅ 삭제 중에는 모달 오버레이로 화면 상호작용 차단 → "한 번에 하나" 보장
    return Scaffold(
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
            Tab(icon: Icon(Icons.settings), text: '리밋 설정'),
          ],
        ),
      ),
      body: Stack(
        children: [
          body,
          if (_isDeletingDivision) ModalBarrier(color: Colors.black26, dismissible: false),
          if (_isDeletingDivision) const Center(child: CircularProgressIndicator()),
          if (_isDeletingDivision && _deletingDivisionName != null)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '삭제 중: ${_deletingDivisionName!}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
