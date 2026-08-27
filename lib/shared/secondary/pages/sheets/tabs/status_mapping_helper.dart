import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../widgets/ops_console_dialogs.dart';
import '../../../widgets/ops_console_widgets.dart';

class StatusMappingHelper extends StatefulWidget {
  const StatusMappingHelper({super.key});

  @override
  State<StatusMappingHelper> createState() => _StatusMappingHelperState();
}

class _AccountCounts {
  const _AccountCounts({
    required this.activeCount,
    required this.inactiveCount,
  });

  final int activeCount;
  final int inactiveCount;

  int get totalCount => activeCount + inactiveCount;

  Map<String, int> toMap() {
    return <String, int>{
      'activeCount': activeCount,
      'inactiveCount': inactiveCount,
      'totalCount': totalCount,
    };
  }
}

class _StatusMappingHelperState extends State<StatusMappingHelper> {
  static const int _maxLimit = 1 << 30;

  final TextEditingController _activeLimitCtrl = TextEditingController();
  final TextEditingController _totalLimitCtrl = TextEditingController();

  String? _selectedDivision;
  String? _selectedArea;
  String? _policyInputKey;
  List<String> _divisions = <String>[];
  List<String> _areas = <String>[];
  bool _loadingScope = true;
  bool _busy = false;
  String? _progressLabel;
  int _progressDone = 0;
  int _progressTotal = 0;

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadDivisions();
  }

  @override
  void dispose() {
    _activeLimitCtrl.dispose();
    _totalLimitCtrl.dispose();
    super.dispose();
  }

  String _showDocId(String division, String area) {
    final d = division.trim().isEmpty ? 'unknownDivision' : division.trim();
    final a = area.trim().isEmpty ? 'unknownArea' : area.trim();
    return '$d-$a';
  }

  DocumentReference<Map<String, dynamic>> _showDocRef(
    String division,
    String area,
  ) {
    return _fs.collection('user_accounts_show').doc(_showDocId(division, area));
  }

  CollectionReference<Map<String, dynamic>> _showUsersCol(
    String division,
    String area,
  ) {
    return _showDocRef(division, area).collection('users');
  }

  int? _asInt(dynamic value) => value is int ? value : null;

  int? _configuredLimit(dynamic value) {
    final parsed = _asInt(value);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  int _nonNegative(dynamic value) {
    final parsed = _asInt(value);
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }

  _AccountCounts _countsFromMeta(Map<String, dynamic> data) {
    final active = _nonNegative(data['activeCount']);
    final inactiveRaw = _asInt(data['inactiveCount']);
    final totalRaw = _asInt(data['totalCount']);
    var inactive = inactiveRaw == null || inactiveRaw < 0 ? 0 : inactiveRaw;
    if ((inactiveRaw == null || inactiveRaw < 0) &&
        totalRaw != null &&
        totalRaw >= active) {
      inactive = totalRaw - active;
    }
    return _AccountCounts(activeCount: active, inactiveCount: inactive);
  }

  Future<void> _loadDivisions() async {
    if (mounted) {
      setState(() => _loadingScope = true);
    }
    try {
      final snap = await _fs
          .collection('divisions')
          .orderBy('name')
          .get(const GetOptions(source: Source.serverAndCache));
      final list = snap.docs
          .map((doc) => (doc.data()['name'] as String?)?.trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _divisions = list;
        if (_selectedDivision == null || !_divisions.contains(_selectedDivision)) {
          _selectedDivision = _divisions.isEmpty ? null : _divisions.first;
        }
      });
      await _loadAreas();
    } catch (error) {
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '회사 목록 로드 실패: $error',
        useCommonUi: true,
      );
    } finally {
      if (mounted) {
        setState(() => _loadingScope = false);
      }
    }
  }

  Future<void> _loadAreas() async {
    final division = _selectedDivision;
    _policyInputKey = null;
    _activeLimitCtrl.clear();
    _totalLimitCtrl.clear();
    if (division == null || division.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _areas = <String>[];
        _selectedArea = null;
      });
      return;
    }
    try {
      final snap = await _fs
          .collection('areas')
          .where('division', isEqualTo: division)
          .orderBy('name')
          .get(const GetOptions(source: Source.serverAndCache));
      final list = snap.docs
          .map((doc) => (doc.data()['name'] as String?)?.trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _areas = list;
        if (_selectedArea == null || !_areas.contains(_selectedArea)) {
          _selectedArea = _areas.isEmpty ? null : _areas.first;
        }
      });
    } catch (error) {
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '지역 목록 로드 실패: $error',
        useCommonUi: true,
      );
    }
  }

  int? _parseLimit(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final parsed = int.tryParse(normalized);
    if (parsed == null || parsed < 0 || parsed > _maxLimit) return null;
    return parsed;
  }

  void _syncPolicyInputs(
    String key,
    int? activeLimit,
    int? totalLimit,
  ) {
    if (_policyInputKey == key) return;
    _policyInputKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _policyInputKey != key) return;
      _activeLimitCtrl.text = activeLimit?.toString() ?? '';
      _totalLimitCtrl.text = totalLimit?.toString() ?? '';
    });
  }

  Future<void> _saveLimits({
    required String division,
    required String area,
  }) async {
    if (_busy) return;
    final activeLimit = _parseLimit(_activeLimitCtrl.text);
    final totalLimit = _parseLimit(_totalLimitCtrl.text);
    if (activeLimit == null || totalLimit == null) {
      showFailedSnackbar(
        context,
        '활성 계정 제한과 전체 계정 제한을 0 이상 $_maxLimit 이하의 정수로 입력하세요.',
        useCommonUi: true,
      );
      return;
    }
    if (activeLimit > totalLimit) {
      showFailedSnackbar(
        context,
        '활성 계정 제한은 전체 계정 제한보다 클 수 없습니다.',
        useCommonUi: true,
      );
      return;
    }
    setState(() => _busy = true);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '계정 리밋 저장',
      initialMessage: '계정 리밋 저장 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 계정 리밋 저장 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 계정 리밋 저장 로그를 콘솔에 기록합니다.',
    );
    try {
      trace.log(
        '대상 확인: division=$division, area=$area, activeLimit=$activeLimit, totalLimit=$totalLimit',
        progress: .22,
      );
      await _showDocRef(division, area).set(
        <String, dynamic>{
          'division': division,
          'area': area,
          'activeLimit': activeLimit,
          'totalLimit': totalLimit,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      trace.log('user_accounts_show 메타 리밋 저장 완료', progress: .9);
      await trace.succeed('계정 리밋 저장이 완료되었습니다.');
      if (!mounted || trace.developerMode) return;
      showSuccessSnackbar(context, '리밋 저장을 완료했습니다.', useCommonUi: true);
    } catch (error, stackTrace) {
      await trace.fail(
        '계정 리밋 저장 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      showFailedSnackbar(context, '저장 실패: $error', useCommonUi: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<_AccountCounts> _rebuildCountsForOne({
    required String division,
    required String area,
    DeveloperOperationTrace? trace,
    double progress = .55,
  }) async {
    trace?.log(
      'projection 계정 조회 시작: division=$division, area=$area',
      progress: progress,
    );
    final users = await _showUsersCol(division, area)
        .get(const GetOptions(source: Source.server));
    var active = 0;
    var inactive = 0;
    for (final doc in users.docs) {
      final isActive = (doc.data()['isActive'] as bool?) ?? true;
      if (isActive) {
        active += 1;
      } else {
        inactive += 1;
      }
    }
    final counts = _AccountCounts(
      activeCount: active,
      inactiveCount: inactive,
    );
    await _showDocRef(division, area).set(
      <String, dynamic>{
        'division': division,
        'area': area,
        ...counts.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    trace?.log(
      '카운트 저장 완료: active=$active, inactive=$inactive, total=${counts.totalCount}',
      progress: progress,
    );
    return counts;
  }

  Future<void> _rebuildSelectedCounts({
    required String division,
    required String area,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '지역 계정 카운트 리빌드',
      initialMessage: '지역 계정 카운트 리빌드를 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 카운트 리빌드 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 카운트 리빌드 로그를 콘솔에 기록합니다.',
    );
    try {
      final counts = await _rebuildCountsForOne(
        division: division,
        area: area,
        trace: trace,
      );
      await trace.succeed(
        '카운트 리빌드 완료: 활성 ${counts.activeCount}, 비활성 ${counts.inactiveCount}, 전체 ${counts.totalCount}',
      );
      if (!mounted || trace.developerMode) return;
      showSuccessSnackbar(
        context,
        '리빌드 완료: 활성 ${counts.activeCount}, 비활성 ${counts.inactiveCount}, 전체 ${counts.totalCount}',
        useCommonUi: true,
      );
    } catch (error, stackTrace) {
      await trace.fail(
        '지역 계정 카운트 리빌드 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      showFailedSnackbar(context, '리빌드 실패: $error', useCommonUi: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _rebuildCountsForDivision(String division) async {
    if (_busy) return;
    final confirmed = await showOpsConfirmDialog(
      context: context,
      title: '회사 전체 카운트 리빌드',
      message: '"$division" 회사의 모든 지역에서 계정 projection을 다시 집계합니다.',
      confirmLabel: '리빌드',
      icon: Icons.playlist_add_check_rounded,
      barrierDismissible: false,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _progressLabel = '회사 전체 지역 목록을 확인하는 중입니다.';
      _progressDone = 0;
      _progressTotal = 0;
    });
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '회사 전체 계정 카운트 리빌드',
      initialMessage: '회사 전체 계정 카운트 리빌드를 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 회사 전체 리빌드 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 회사 전체 리빌드 로그를 콘솔에 기록합니다.',
    );
    try {
      final areasSnap = await _fs
          .collection('areas')
          .where('division', isEqualTo: division)
          .orderBy('name')
          .get(const GetOptions(source: Source.server));
      final areas = areasSnap.docs
          .map((doc) => (doc.data()['name'] as String?)?.trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      trace.log('대상 지역 확인 완료: ${areas.length}개', progress: .12);
      if (!mounted) return;
      setState(() {
        _progressTotal = areas.length;
        _progressDone = 0;
      });
      for (var index = 0; index < areas.length; index++) {
        final area = areas[index];
        if (!mounted) return;
        setState(() {
          _progressLabel = '리빌드 진행: $division / $area';
        });
        final progress = areas.isEmpty ? .85 : .18 + ((index + 1) / areas.length) * .68;
        await _rebuildCountsForOne(
          division: division,
          area: area,
          trace: trace,
          progress: progress,
        );
        if (!mounted) return;
        setState(() => _progressDone = index + 1);
      }
      await trace.succeed('회사 "$division" 계정 카운트 리빌드가 완료되었습니다.');
      if (!mounted || trace.developerMode) return;
      showSuccessSnackbar(
        context,
        '회사 "$division" 계정 수 리빌드 완료',
        useCommonUi: true,
      );
    } catch (error, stackTrace) {
      await trace.fail(
        '회사 전체 계정 카운트 리빌드 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      showFailedSnackbar(
        context,
        '회사 전체 리빌드 실패: $error',
        useCommonUi: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progressLabel = null;
          _progressDone = 0;
          _progressTotal = 0;
        });
      }
    }
  }

  Widget _buildListRow({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    Color? tone,
  }) {
    final tokens = CommonUiTheme.of(context);
    final foreground = tone ?? tokens.iconSecondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: foreground.withOpacity(.1),
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 19, color: foreground),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: tone ?? tokens.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeSurface() {
    final division = _selectedDivision;
    final area = _selectedArea;
    return OpsDockListSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: OpsSectionTitle(
              title: '관리 범위',
              subtitle: '계정 정책을 확인할 회사와 지역을 선택합니다.',
              icon: Icons.account_tree_rounded,
              trailing: _loadingScope
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          ),
          const OpsDivider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: division,
                  isExpanded: true,
                  items: _divisions
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) async {
                          setState(() {
                            _selectedDivision = value;
                            _selectedArea = null;
                            _areas = <String>[];
                          });
                          await _loadAreas();
                        },
                  decoration: opsInputDecoration(
                    context,
                    label: '회사 선택',
                    prefixIcon: const Icon(Icons.business_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: area,
                  isExpanded: true,
                  items: _areas
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() {
                            _selectedArea = value;
                            _policyInputKey = null;
                            _activeLimitCtrl.clear();
                            _totalLimitCtrl.clear();
                          });
                        },
                  decoration: opsInputDecoration(
                    context,
                    label: '지역 선택',
                    prefixIcon: const Icon(Icons.location_on_rounded),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicySurface() {
    final division = _selectedDivision;
    final area = _selectedArea;
    if (division == null || area == null) {
      return const OpsDockListSurface(
        child: SizedBox(
          height: 260,
          child: OpsEmptyState(
            icon: Icons.tune_rounded,
            title: '회사와 지역을 선택하세요',
            message: '선택한 범위의 현재 계정 수와 생성 리밋을 관리할 수 있습니다.',
          ),
        ),
      );
    }
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tokens = CommonUiTheme.of(context);
    return OpsDockListSurface(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _showDocRef(division, area).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return SizedBox(
              height: 260,
              child: OpsEmptyState(
                icon: Icons.error_outline_rounded,
                title: '계정 정책을 불러오지 못했습니다',
                message: snapshot.error.toString(),
              ),
            );
          }
          final data = snapshot.data?.data() ?? <String, dynamic>{};
          final exists = snapshot.data?.exists ?? false;
          final counts = _countsFromMeta(data);
          final activeLimit = _configuredLimit(data['activeLimit']);
          final totalLimit = _configuredLimit(data['totalLimit']);
          final configured = activeLimit != null && totalLimit != null;
          final activeWarning = activeLimit != null && counts.activeCount > activeLimit;
          final totalWarning = totalLimit != null && counts.totalCount > totalLimit;
          _syncPolicyInputs(
            '$division-$area',
            activeLimit,
            totalLimit,
          );
          return AnimatedSize(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
            curve: CommonUiMotion.standard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: OpsSectionTitle(
                    title: '계정 정책',
                    subtitle: '신규 계정 생성 전에 활성/전체 리밋이 모두 설정되어 있어야 합니다.',
                    icon: Icons.manage_accounts_rounded,
                    trailing: OpsStatusBadge(
                      label: configured ? '리밋 설정됨' : '리밋 미설정',
                      color: configured ? tokens.success : tokens.warning,
                      icon: configured ? Icons.check_rounded : Icons.priority_high_rounded,
                    ),
                  ),
                ),
                const OpsDivider(),
                _buildListRow(
                  icon: Icons.person_rounded,
                  title: '활성 계정',
                  subtitle: activeLimit == null ? '활성 계정 리밋을 설정해야 신규 계정을 생성할 수 있습니다.' : '현재 활성 projection 수 / 설정 리밋',
                  value: '${counts.activeCount} / ${activeLimit ?? '-'}',
                  tone: activeWarning ? tokens.danger : tokens.success,
                ),
                const OpsDivider(),
                _buildListRow(
                  icon: Icons.person_off_rounded,
                  title: '비활성 계정',
                  subtitle: '현재 비활성 projection 수',
                  value: '${counts.inactiveCount}',
                ),
                const OpsDivider(),
                _buildListRow(
                  icon: Icons.groups_rounded,
                  title: '전체 계정',
                  subtitle: totalLimit == null ? '전체 계정 리밋을 설정해야 신규 계정을 생성할 수 있습니다.' : '현재 전체 projection 수 / 설정 리밋',
                  value: '${counts.totalCount} / ${totalLimit ?? '-'}',
                  tone: totalWarning ? tokens.danger : tokens.info,
                ),
                if (!exists || activeWarning || totalWarning) ...[
                  const OpsDivider(),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: OpsInlineMessage(
                      message: !exists
                          ? '계정 메타 문서가 없습니다. 리밋을 저장하거나 카운트를 리빌드하면 생성됩니다.'
                          : activeWarning && totalWarning
                              ? '활성 계정과 전체 계정 수가 설정 리밋을 초과했습니다.'
                              : activeWarning
                                  ? '활성 계정 수가 설정 리밋을 초과했습니다.'
                                  : '전체 계정 수가 설정 리밋을 초과했습니다.',
                      danger: activeWarning || totalWarning,
                      icon: activeWarning || totalWarning
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline_rounded,
                    ),
                  ),
                ],
                const OpsDivider(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _activeLimitCtrl,
                        keyboardType: TextInputType.number,
                        enabled: !_busy,
                        decoration: opsInputDecoration(
                          context,
                          label: '활성 계정 제한',
                          prefixIcon: const Icon(Icons.person_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _totalLimitCtrl,
                        keyboardType: TextInputType.number,
                        enabled: !_busy,
                        decoration: opsInputDecoration(
                          context,
                          label: '전체 계정 제한',
                          prefixIcon: const Icon(Icons.groups_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OpsActionButton(
                        label: _busy ? '처리 중' : '리밋 저장',
                        icon: _busy ? Icons.hourglass_top_rounded : Icons.save_rounded,
                        onPressed: _busy
                            ? null
                            : () => _saveLimits(
                                  division: division,
                                  area: area,
                                ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMaintenanceSurface() {
    final division = _selectedDivision;
    final area = _selectedArea;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final progress = _progressTotal <= 0
        ? null
        : (_progressDone / _progressTotal).clamp(0.0, 1.0).toDouble();
    return OpsDockListSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: OpsSectionTitle(
              title: '카운트 유지보수',
              subtitle: 'projection users를 기준으로 active/inactive/totalCount를 다시 계산합니다.',
              icon: Icons.sync_rounded,
            ),
          ),
          const OpsDivider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OpsActionButton(
                  label: '선택 지역 카운트 리빌드',
                  icon: Icons.refresh_rounded,
                  tonal: true,
                  onPressed: _busy || division == null || area == null
                      ? null
                      : () => _rebuildSelectedCounts(
                            division: division,
                            area: area,
                          ),
                ),
                const SizedBox(height: 8),
                OpsActionButton(
                  label: '회사 전체 카운트 리빌드',
                  icon: Icons.playlist_add_check_rounded,
                  tonal: true,
                  onPressed: _busy || division == null
                      ? null
                      : () => _rebuildCountsForDivision(division),
                ),
                AnimatedSize(
                  duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
                  curve: CommonUiMotion.standard,
                  child: _progressLabel == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AnimatedSwitcher(
                                duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                                child: Text(
                                  _progressLabel!,
                                  key: ValueKey<String>(_progressLabel!),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: CommonUiTheme.of(context).textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(value: progress),
                              if (_progressTotal > 0) ...[
                                const SizedBox(height: 5),
                                Text(
                                  '$_progressDone / $_progressTotal',
                                  textAlign: TextAlign.end,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: CommonUiTheme.of(context).textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        CommonAnimatedReveal(
          offset: const Offset(0, .018),
          child: _buildScopeSurface(),
        ),
        const SizedBox(height: 10),
        CommonAnimatedReveal(
          delay: reduceMotion ? Duration.zero : const Duration(milliseconds: 35),
          offset: const Offset(0, .018),
          child: _buildPolicySurface(),
        ),
        const SizedBox(height: 10),
        CommonAnimatedReveal(
          delay: reduceMotion ? Duration.zero : const Duration(milliseconds: 70),
          offset: const Offset(0, .018),
          child: _buildMaintenanceSurface(),
        ),
      ],
    );
  }
}
