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

class _AreaManagementState extends State<AreaManagement>
    with SingleTickerProviderStateMixin {
  /// 탭 구성
  /// 0: AddAreaTab (지역 추가)
  /// 1: DivisionManagementTab (회사 관리)
  /// 2: UserAccountsTab (계정 조회/관리)
  /// 3: StatusMappingHelper (리밋 설정)
  late final TabController _tabController;

  // 상태
  String? _selectedDivision;
  List<String> _divisionList = [];

  String? _accountSelectedDivision;
  String? _accountSelectedArea;

  bool _isDeletingDivision = false;
  String? _deletingDivisionName;

  // 최초 진입용 오버레이 표시 여부
  bool _showIntroOverlay = true;

  // 지연 로딩 플래그
  bool _divisionsLoaded = false;

  @override
  void initState() {
    super.initState();
    // ✅ 가시 탭 4개만 관리 (숨은 탭 없음 → 탭 공간 0)
    _tabController = TabController(length: 4, vsync: this, initialIndex: 0);

    // 사용자가 탭을 직접 전환했을 때, 0/1/2에 첫 진입하면 로드
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final i = _tabController.index;
      if (!_divisionsLoaded && (i == 0 || i == 1 || i == 2)) {
        _divisionsLoaded = true;
        _loadDivisions();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------
  // Firestore: divisions 로드/추가/삭제
  // ---------------------------
  Future<void> _loadDivisions() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('divisions')
          .orderBy('name')
          .get();

      // ✅ 계측: read
      try {
        await UsageReporter.instance.report(
          area: 'AreaManagement',
          action: 'read',
          n: snap.docs.length,
          source: 'AreaManagement._loadDivisions.divisions.get',
        );
      } catch (_) {}

      final divisions = snap.docs
          .map((e) => (e['name'] as String?)?.trim())
          .whereType<String>()
          .toList()
        ..sort();

      if (!mounted) return;
      setState(() {
        _divisionList = divisions;

        // 선택값 보정
        if (_selectedDivision != null &&
            !_divisionList.contains(_selectedDivision)) {
          _selectedDivision = null;
        }
        if (_accountSelectedDivision != null &&
            !_divisionList.contains(_accountSelectedDivision)) {
          _accountSelectedDivision = null;
          _accountSelectedArea = null;
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
      await FirebaseFirestore.instance
          .collection('divisions')
          .doc(trimmed)
          .set({
        'name': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ✅ 계측: write
      try {
        await UsageReporter.instance.report(
          area: 'AreaManagement',
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
    if (_isDeletingDivision) return;

    setState(() {
      _isDeletingDivision = true;
      _deletingDivisionName = name;
    });

    try {
      final fs = FirebaseFirestore.instance;
      final divRef = fs.collection('divisions').doc(name);
      final areasSnap =
      await fs.collection('areas').where('division', isEqualTo: name).get();

      // ✅ 계측: read(연쇄 삭제 대상 조회 규모)
      try {
        await UsageReporter.instance.report(
          area: 'AreaManagement',
          action: 'read',
          n: areasSnap.docs.length,
          source: 'AreaManagement._deleteDivision.areas.queryForCascade',
        );
      } catch (_) {}

      // 대량 삭제: 배치 커밋
      WriteBatch batch = fs.batch();
      int ops = 0;

      batch.delete(divRef);
      ops++;

      for (final doc in areasSnap.docs) {
        batch.delete(doc.reference);
        ops++;

        if (ops >= 450) {
          await batch.commit();
          // ✅ 계측: 중간 커밋
          try {
            await UsageReporter.instance.report(
              area: 'AreaManagement',
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
        // ✅ 계측: 마지막 커밋
        try {
          await UsageReporter.instance.report(
            area: 'AreaManagement',
            action: 'delete',
            n: ops,
            source: 'AreaManagement._deleteDivision.batch.commit.final',
          );
        } catch (_) {}
      }

      await _loadDivisions();

      if (!mounted) return;
      showSuccessSnackbar(context, '✅ 회사 "$name" 삭제됨');
    } catch (e) {
      if (mounted) {
        showFailedSnackbar(context, '❌ 삭제 실패: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingDivision = false;
          _deletingDivisionName = null;
        });
      }
    }
  }

  // ---------------------------
  // UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final body = TabBarView(
      controller: _tabController,
      children: [
        // 0: 지역 추가
        AddAreaTab(
          selectedDivision: _selectedDivision,
          divisionList: _divisionList,
          onDivisionChanged: (val) => setState(() => _selectedDivision = val),
        ),

        // 1: 회사 관리
        DivisionManagementTab(
          divisionList: _divisionList,
          onDivisionAdded: _addDivision,
          onDivisionDeleted: _deleteDivision,
        ),

        // 2: 계정 조회/관리
        UserAccountsTab(
          selectedDivision: _accountSelectedDivision,
          selectedArea: _accountSelectedArea,
          onDivisionChanged: (val) {
            setState(() {
              _accountSelectedDivision = val;
              _accountSelectedArea = null;
            });
          },
          onAreaChanged: (val) =>
              setState(() => _accountSelectedArea = val),
        ),

        // 3: 리밋 설정
        const StatusMappingHelper(),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('지역 및 회사 관리',
            style: TextStyle(fontWeight: FontWeight.bold)),
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

          // ✅ 초기 진입용 풀스크린 오버레이(세로 정렬, 한 줄에 하나씩)
          if (_showIntroOverlay)
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Colors.white),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '지역/회사 관리 시작',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 여기부터: Wrap → Column(세로 정렬 + 가득 너비)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1) 지역 추가 (Filled)
                            FilledButton(
                              onPressed: () {
                                if (!_divisionsLoaded) {
                                  _divisionsLoaded = true;
                                  _loadDivisions();
                                }
                                setState(() => _showIntroOverlay = false);
                                _tabController.index = 0; // 지역 추가
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text('지역 추가', textAlign: TextAlign.center),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 2) 회사 관리
                            OutlinedButton(
                              onPressed: () {
                                if (!_divisionsLoaded) {
                                  _divisionsLoaded = true;
                                  _loadDivisions();
                                }
                                setState(() => _showIntroOverlay = false);
                                _tabController.index = 1; // 회사 관리
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text('회사 관리', textAlign: TextAlign.center),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 3) 계정 조회/관리
                            OutlinedButton(
                              onPressed: () {
                                if (!_divisionsLoaded) {
                                  _divisionsLoaded = true;
                                  _loadDivisions();
                                }
                                setState(() => _showIntroOverlay = false);
                                _tabController.index = 2; // 계정 조회/관리
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child:
                                Text('계정 조회/관리', textAlign: TextAlign.center),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 4) 리밋 설정
                            OutlinedButton(
                              onPressed: () {
                                setState(() => _showIntroOverlay = false);
                                _tabController.index = 3; // 리밋 설정
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text('리밋 설정', textAlign: TextAlign.center),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                        const Text(
                          '※ 이 화면은 최초 진입 안내이며 탭 목록에는 표시되지 않습니다.',
                          style: TextStyle(color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (_isDeletingDivision)
            ModalBarrier(color: Colors.black26, dismissible: false),
          if (_isDeletingDivision)
            const Center(child: CircularProgressIndicator()),
          if (_isDeletingDivision && _deletingDivisionName != null)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
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
