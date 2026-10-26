import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../features/account/data/services/company_bootstrap_service.dart';

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
          .where((doc) => doc.data()['lifecycleStatus'] != 'closed')
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

      final settings = request.settings;
      trace.log(
        '생성 스키마 확인: division=$name modes=${DevAreaModePolicy.canonicalModes.join(',')} capabilities=${settings.capabilityKeys.join(',')} thirdPartyFields=excluded limits=${settings.activeLimit ?? 'unset'}/${settings.totalLimit ?? 'unset'}',
        progress: 0.14,
      );
      trace.log(
        '본사 정책 적용: canonicalModes=single,double,triple,minor modeSelector=disabled',
        progress: 0.2,
      );
      await const CompanyBootstrapService().createCompany(
        company: name,
        divisionData: <String, dynamic>{
          'name': name,
          'createdAt': FieldValue.serverTimestamp(),
        },
        areaData: settings.headquarterAreaPayload(name: name, division: name),
        metaData: settings.accountMetaPayload(
          division: name,
          area: name,
          activeCount: 0,
          inactiveCount: 0,
        ),
      );
      trace.log('Firestore transaction commit 완료: company_bootstrap included', progress: 0.88);
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
      title: '회사 폐쇄',
      initialMessage: '회사 폐쇄 전 계정과 초기화 기록을 검증합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 회사 폐쇄 로그의 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 회사 폐쇄 로그를 콘솔에 기록합니다.',
    );
    try {
      trace.log('회사 폐쇄 요청: company=$name', progress: 0.12);
      await const CompanyBootstrapService().closeCompany(company: name);
      trace.log('회사 폐쇄 및 전체 초기 관리자 접근 목록 동기화 완료', progress: 0.9);
      await _loadDivisions();
      await trace.succeed('회사 폐쇄와 접근 목록 동기화가 완료되었습니다.');
      if (!mounted) return true;
      if (!trace.developerMode) {
        showSuccessSnackbar(context, '회사 "$name"이 폐쇄되었습니다.', useCommonUi: true);
      }
      return true;
    } catch (error, stackTrace) {
      await trace.fail('회사 폐쇄 또는 접근 목록 동기화에 실패했습니다.',
        error: error, stackTrace: stackTrace);
      if (!mounted) return false;
      if (!trace.developerMode) {
        final raw = error.toString();
        final message = raw.contains('COMPANY_CLOSED_SYNC_PENDING')
            ? '회사 폐쇄는 완료됐지만 다른 관리자 접근 목록 동기화가 남아 있습니다. 런처 도움말에서 재동기화하세요.'
            : raw.contains('COMPANY_CLOSE_RELATED_ACCOUNT_EXISTS')
                ? '다른 소속 계정이 남아 있어 회사를 폐쇄할 수 없습니다.'
            : raw.contains('COMPANY_CLOSE_INTEGRITY_REVIEW_REQUIRED')
                ? '초기 관리자 또는 계정 메타데이터 정합성을 확인해야 합니다.'
                : '회사 폐쇄 또는 접근 목록 동기화 실패: $error';
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
