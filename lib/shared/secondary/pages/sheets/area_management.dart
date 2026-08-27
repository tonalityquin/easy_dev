import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import 'tabs/add_area_tab.dart';
import 'tabs/dev_management_common.dart';
import 'tabs/division_management_tab.dart';
import 'tabs/status_mapping_helper.dart';
import 'tabs/user_account_tab.dart';
import '../../widgets/ops_console_widgets.dart';

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
  bool _loadingDivisions = false;

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
    if (_loadingDivisions) return;
    setState(() => _loadingDivisions = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('divisions')
          .orderBy('name')
          .get(const GetOptions(source: Source.serverAndCache));
      final divisions = snap.docs
          .map((doc) => (doc.data()['name'] ?? '').toString().trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _divisionList = divisions;
        if (_selectedDivision != null && !_divisionList.contains(_selectedDivision)) {
          _selectedDivision = null;
        }
        if (_accountSelectedDivision != null && !_divisionList.contains(_accountSelectedDivision)) {
          _accountSelectedDivision = null;
          _accountSelectedArea = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '회사 목록 로드 실패: $error',
        useCommonUi: true,
      );
    } finally {
      if (mounted) setState(() => _loadingDivisions = false);
    }
  }

  Future<bool> _addDivision(DivisionCreateRequest request) async {
    final name = request.name.trim();
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '회사 및 본사 생성',
      initialMessage: '회사와 본사 지역 생성 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 회사 생성 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 회사 생성 로그를 콘솔에 기록합니다.',
    );
    try {
      final firestore = FirebaseFirestore.instance;
      final divisionRef = firestore.collection('divisions').doc(name);
      final headquarterRef = firestore.collection('areas').doc('$name-$name');
      final accountMetaRef = firestore.collection('user_accounts_show').doc('$name-$name');
      final settings = request.settings;
      trace.log(
        '생성 스키마 확인: division=$name modes=${DevAreaModePolicy.canonicalModes.join(',')} capabilities=${settings.capabilityKeys.join(',')} thirdPartyFields=excluded limits=${settings.activeLimit ?? 'unset'}/${settings.totalLimit ?? 'unset'}',
        progress: 0.14,
      );
      trace.log(
        '본사 정책 적용: canonicalModes=single,double,triple,minor modeSelector=disabled',
        progress: 0.2,
      );
      await firestore.runTransaction((transaction) async {
        final divisionSnap = await transaction.get(divisionRef);
        final headquarterSnap = await transaction.get(headquarterRef);
        final accountMetaSnap = await transaction.get(accountMetaRef);
        if (divisionSnap.exists) {
          throw StateError('DIVISION_ALREADY_EXISTS');
        }
        if (headquarterSnap.exists) {
          throw StateError('HEADQUARTER_ALREADY_EXISTS');
        }
        if (accountMetaSnap.exists) {
          throw StateError('HEADQUARTER_ACCOUNT_META_ALREADY_EXISTS');
        }
        trace.log('중복 문서 검사 완료: reads=3', progress: 0.38);
        transaction.set(
          divisionRef,
          <String, dynamic>{
            'name': name,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
        transaction.set(
          headquarterRef,
          settings.headquarterAreaPayload(
            name: name,
            division: name,
          ),
        );
        transaction.set(
          accountMetaRef,
          settings.accountMetaPayload(
            division: name,
            area: name,
            activeCount: 0,
            inactiveCount: 0,
          ),
        );
      });
      trace.log('Firestore transaction commit 완료: writes=3', progress: 0.88);
      await _loadDivisions();
      await trace.succeed('회사와 본사 지역 생성이 완료되었습니다.');
      if (!mounted) return true;
      if (!trace.developerMode) {
        showSuccessSnackbar(
          context,
          '회사 "$name"과 본사 지역이 생성되었습니다.',
          useCommonUi: true,
        );
      }
      return true;
    } catch (error, stackTrace) {
      await trace.fail(
        '회사 및 본사 생성에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return false;
      if (!trace.developerMode) {
        final raw = error.toString();
        final message = raw.contains('DIVISION_ALREADY_EXISTS')
            ? '이미 등록된 회사입니다.'
            : raw.contains('HEADQUARTER_ALREADY_EXISTS')
                ? '동일한 본사 지역 문서가 이미 존재합니다.'
                : raw.contains('HEADQUARTER_ACCOUNT_META_ALREADY_EXISTS')
                    ? '동일한 본사 계정 메타 문서가 이미 존재합니다.'
                    : '회사 생성 실패: $error';
        showFailedSnackbar(context, message, useCommonUi: true);
      }
      return false;
    }
  }

  Future<bool> _deleteDivision(String name) async {
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '회사 삭제',
      initialMessage: '회사 삭제 전 연관 문서 검사를 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 회사 삭제 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 회사 삭제 로그를 콘솔에 기록합니다.',
    );
    try {
      final firestore = FirebaseFirestore.instance;
      final divisionRef = firestore.collection('divisions').doc(name);
      final areasSnap = await firestore
          .collection('areas')
          .where('division', isEqualTo: name)
          .get(const GetOptions(source: Source.server));
      final accountSnap = await firestore
          .collection('user_accounts')
          .where('divisions', arrayContains: name)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      trace.log(
        '연관 문서 검사: areas=${areasSnap.docs.length} accountExists=${accountSnap.docs.isNotEmpty}',
        progress: 0.24,
      );
      if (accountSnap.docs.isNotEmpty) {
        throw StateError('RELATED_USER_ACCOUNT_EXISTS');
      }
      for (final areaDoc in areasSnap.docs) {
        final areaName = (areaDoc.data()['name'] ?? '').toString().trim();
        if (areaName.isEmpty) continue;
        final showRef = firestore.collection('user_accounts_show').doc('$name-$areaName');
        final projectionSnap = await showRef
            .collection('users')
            .limit(1)
            .get(const GetOptions(source: Source.server));
        if (projectionSnap.docs.isNotEmpty) {
          throw StateError('RELATED_USER_PROJECTION_EXISTS:$areaName');
        }
      }
      trace.log('계정 원본 및 projection 비어 있음 확인 완료', progress: 0.46);
      final refs = <DocumentReference<Map<String, dynamic>>>[
        divisionRef,
        for (final areaDoc in areasSnap.docs) areaDoc.reference,
        for (final areaDoc in areasSnap.docs)
          if ((areaDoc.data()['name'] ?? '').toString().trim().isNotEmpty)
            firestore
                .collection('user_accounts_show')
                .doc('$name-${(areaDoc.data()['name'] ?? '').toString().trim()}'),
      ];
      var index = 0;
      while (index < refs.length) {
        final end = (index + 430 < refs.length) ? index + 430 : refs.length;
        final batch = firestore.batch();
        for (final ref in refs.sublist(index, end)) {
          batch.delete(ref);
        }
        await batch.commit();
        index = end;
        trace.log('삭제 batch commit: $index/${refs.length}', progress: 0.46 + 0.42 * (index / refs.length));
      }
      await _loadDivisions();
      await trace.succeed('회사, 소속 지역, 계정 메타 삭제가 완료되었습니다.');
      if (!mounted) return true;
      if (!trace.developerMode) {
        showSuccessSnackbar(
          context,
          '회사 "$name"이 삭제되었습니다.',
          useCommonUi: true,
        );
      }
      return true;
    } catch (error, stackTrace) {
      await trace.fail(
        '회사 삭제에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return false;
      if (!trace.developerMode) {
        final raw = error.toString();
        final message = raw.contains('RELATED_USER_ACCOUNT_EXISTS')
            ? '소속 계정이 남아 있어 회사를 삭제할 수 없습니다.'
            : raw.contains('RELATED_USER_PROJECTION_EXISTS')
                ? '계정 projection이 남아 있어 회사를 삭제할 수 없습니다.'
                : '회사 삭제 실패: $error';
        showFailedSnackbar(context, message, useCommonUi: true);
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final embedded = OpsConsolePresentationScope.isEmbedded(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
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
          divisionList: _divisionList,
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

    final tabBar = TabBar(
      controller: _tabController,
      isScrollable: embedded,
      indicatorColor: tokens.accent,
      labelColor: tokens.accent,
      unselectedLabelColor: tokens.textSecondary,
      dividerColor: tokens.borderSubtle,
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
      tabs: embedded
          ? const [
              Tab(icon: Icon(Icons.location_city, size: 17), text: '지역'),
              Tab(icon: Icon(Icons.business, size: 17), text: '회사'),
              Tab(icon: Icon(Icons.manage_accounts, size: 17), text: '계정'),
              Tab(icon: Icon(Icons.settings, size: 17), text: '리밋'),
            ]
          : const [
              Tab(icon: Icon(Icons.location_city), text: '지역 관리'),
              Tab(icon: Icon(Icons.business), text: '회사 관리'),
              Tab(icon: Icon(Icons.manage_accounts), text: '계정 관리'),
              Tab(icon: Icon(Icons.settings), text: '리밋 관리'),
            ],
    );

    if (embedded) {
      return Material(
        color: tokens.canvas,
        child: Column(
          children: [
            Material(
              color: tokens.surfaceRaised,
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  tabBar,
                  AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    child: _loadingDivisions
                        ? const Padding(
                            key: ValueKey<String>('division_load_progress'),
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey<String>('division_load_idle')),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

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
        bottom: tabBar,
      ),
      body: body,
    );
  }
}
