import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import 'tabs/add_area_tab.dart';
import 'tabs/division_management_tab.dart';
import 'tabs/status_mapping_helper.dart';
import 'tabs/user_account_tab.dart';

class AreaManagement extends StatefulWidget {
  const AreaManagement({super.key});

  @override
  State<AreaManagement> createState() => _AreaManagementState();
}

class _AreaManagementState extends State<AreaManagement>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _selectedDivision;
  List<String> _divisionList = <String>[];
  String? _accountSelectedDivision;
  String? _accountSelectedArea;
  bool _isDeletingDivision = false;
  String? _deletingDivisionName;
  bool _showIntroOverlay = true;
  bool _divisionsLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (!_divisionsLoaded) {
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

  Future<void> _loadDivisions() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('divisions')
          .orderBy('name')
          .get();
      final divisions = snap.docs
          .map((doc) => (doc['name'] as String?)?.trim())
          .whereType<String>()
          .toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _divisionList = divisions;
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
    } catch (error) {
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '회사 목록 로드 실패: $error',
        usePromptUi: true,
      );
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
      await _loadDivisions();
      if (!mounted) return;
      showSuccessSnackbar(
        context,
        '회사 "$trimmed" 추가됨',
        usePromptUi: true,
      );
    } catch (error) {
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '추가 실패: $error',
        usePromptUi: true,
      );
    }
  }

  Future<void> _deleteDivision(String name) async {
    if (_isDeletingDivision) return;
    setState(() {
      _isDeletingDivision = true;
      _deletingDivisionName = name;
    });
    try {
      final firestore = FirebaseFirestore.instance;
      final divisionRef = firestore.collection('divisions').doc(name);
      final areasSnap = await firestore
          .collection('areas')
          .where('division', isEqualTo: name)
          .get();
      WriteBatch batch = firestore.batch();
      var operations = 0;
      batch.delete(divisionRef);
      operations++;
      for (final doc in areasSnap.docs) {
        batch.delete(doc.reference);
        operations++;
        if (operations >= 450) {
          await batch.commit();
          batch = firestore.batch();
          operations = 0;
        }
      }
      if (operations > 0) {
        await batch.commit();
      }
      await _loadDivisions();
      if (!mounted) return;
      showSuccessSnackbar(
        context,
        '회사 "$name" 삭제됨',
        usePromptUi: true,
      );
    } catch (error) {
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '삭제 실패: $error',
        usePromptUi: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingDivision = false;
          _deletingDivisionName = null;
        });
      }
    }
  }

  void _openTab(int index) {
    if (!_divisionsLoaded) {
      _divisionsLoaded = true;
      _loadDivisions();
    }
    setState(() => _showIntroOverlay = false);
    _tabController.index = index;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final body = TabBarView(
      controller: _tabController,
      children: [
        AddAreaTab(
          selectedDivision: _selectedDivision,
          divisionList: _divisionList,
          onDivisionChanged: (value) {
            setState(() => _selectedDivision = value);
          },
        ),
        DivisionManagementTab(
          divisionList: _divisionList,
          onDivisionAdded: _addDivision,
          onDivisionDeleted: _deleteDivision,
        ),
        UserAccountsTab(
          selectedDivision: _accountSelectedDivision,
          selectedArea: _accountSelectedArea,
          onDivisionChanged: (value) {
            setState(() {
              _accountSelectedDivision = value;
              _accountSelectedArea = null;
            });
          },
          onAreaChanged: (value) {
            setState(() => _accountSelectedArea = value);
          },
        ),
        const StatusMappingHelper(),
      ],
    );

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: tokens.surfaceRaised,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: tokens.transparent,
        elevation: 0,
        title: Text(
          '지역 및 회사 관리',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: tokens.accent,
          labelColor: tokens.accent,
          unselectedLabelColor: tokens.textSecondary,
          dividerColor: tokens.borderSubtle,
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
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_showIntroOverlay,
              child: AnimatedOpacity(
                opacity: _showIntroOverlay ? 1 : 0,
                duration: reduceMotion
                    ? Duration.zero
                    : PromptUiMotion.component,
                child: ColoredBox(
                  color: tokens.canvas,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: PromptAnimatedReveal(
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: tokens.surfaceRaised,
                              borderRadius: BorderRadius.circular(
                                PromptUiShapes.card,
                              ),
                              border: Border.all(
                                color: tokens.borderSubtle,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: tokens.shadow,
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: tokens.accentContainer,
                                    borderRadius: BorderRadius.circular(
                                      PromptUiShapes.control,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.corporate_fare_rounded,
                                    color: tokens.onAccentContainer,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '지역/회사 관리 시작',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: tokens.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '관리할 항목을 선택하면 해당 탭으로 이동합니다.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: tokens.textSecondary,
                                      ),
                                ),
                                const SizedBox(height: 18),
                                PromptButton(
                                  label: '지역 추가',
                                  icon: Icons.add_location_alt_rounded,
                                  onPressed: () => _openTab(0),
                                  expand: true,
                                  haptic: PromptHaptic.selection,
                                ),
                                const SizedBox(height: 8),
                                PromptButton(
                                  label: '회사 관리',
                                  icon: Icons.business_rounded,
                                  onPressed: () => _openTab(1),
                                  expand: true,
                                  variant: PromptButtonVariant.secondary,
                                  haptic: PromptHaptic.selection,
                                ),
                                const SizedBox(height: 8),
                                PromptButton(
                                  label: '계정 조회/관리',
                                  icon: Icons.manage_accounts_rounded,
                                  onPressed: () => _openTab(2),
                                  expand: true,
                                  variant: PromptButtonVariant.secondary,
                                  haptic: PromptHaptic.selection,
                                ),
                                const SizedBox(height: 8),
                                PromptButton(
                                  label: '리밋 설정',
                                  icon: Icons.tune_rounded,
                                  onPressed: () => _openTab(3),
                                  expand: true,
                                  variant: PromptButtonVariant.tertiary,
                                  haptic: PromptHaptic.selection,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_isDeletingDivision,
              child: AnimatedOpacity(
                opacity: _isDeletingDivision ? 1 : 0,
                duration: reduceMotion
                    ? Duration.zero
                    : PromptUiMotion.selection,
                child: ColoredBox(
                  color: tokens.scrim,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.surfaceRaised,
                        borderRadius: BorderRadius.circular(
                          PromptUiShapes.control,
                        ),
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: tokens.accent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _deletingDivisionName == null
                                ? '삭제 중'
                                : '삭제 중: $_deletingDivisionName',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
