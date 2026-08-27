import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../app/models/capability.dart';
import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/status_dialog.dart';
import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../widgets/ops_console_dialogs.dart';
import '../../../widgets/ops_console_widgets.dart';
import 'dev_management_common.dart';

class AddAreaTab extends StatefulWidget {
  const AddAreaTab({
    super.key,
    required this.selectedDivision,
    required this.divisionList,
    required this.onDivisionChanged,
  });

  final String? selectedDivision;
  final List<String> divisionList;
  final ValueChanged<String?> onDivisionChanged;

  @override
  State<AddAreaTab> createState() => _AddAreaTabState();
}

class _AddAreaTabState extends State<AddAreaTab> {
  bool _mutating = false;
  String? _deletingAreaName;
  String? _editingAreaId;
  Future<List<DevAreaListItem>>? _areasFuture;

  @override
  void initState() {
    super.initState();
    _areasFuture = _loadAreas();
  }

  @override
  void didUpdateWidget(covariant AddAreaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDivision != widget.selectedDivision) {
      _areasFuture = _loadAreas();
      _editingAreaId = null;
    }
  }

  Future<List<DevAreaListItem>> _loadAreas() async {
    final division = widget.selectedDivision?.trim() ?? '';
    if (division.isEmpty) return const <DevAreaListItem>[];
    final snapshot = await FirebaseFirestore.instance
        .collection('areas')
        .where('division', isEqualTo: division)
        .get(const GetOptions(source: Source.serverAndCache));
    final items = snapshot.docs
        .map(DevAreaListItem.fromDocument)
        .where((item) => item.name.isNotEmpty)
        .toList()
      ..sort((a, b) {
        if (a.isHeadquarter != b.isHeadquarter) return a.isHeadquarter ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return items;
  }

  void _refreshAreas() {
    if (!mounted) return;
    setState(() => _areasFuture = _loadAreas());
  }

  Future<void> _openCreateDialog() async {
    if (_mutating) return;
    final division = widget.selectedDivision?.trim() ?? '';
    if (division.isEmpty) {
      showSelectedSnackbar(
        context,
        '먼저 회사를 선택하세요.',
        useCommonUi: true,
      );
      return;
    }
    final result = await showCommonOverlayDialog<_AreaEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AreaEditorDialog(
        division: division,
        isEdit: false,
      ),
    );
    if (result == null || !mounted) return;
    await _createArea(result);
  }

  Future<void> _createArea(_AreaEditorResult result) async {
    if (_mutating) return;
    final division = widget.selectedDivision?.trim() ?? '';
    if (division.isEmpty) return;
    setState(() => _mutating = true);
    final areaName = result.name;
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '지역 생성',
      initialMessage: '지역과 계정 메타 생성 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 지역 생성 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 지역 생성 로그를 콘솔에 기록합니다.',
    );
    try {
      final firestore = FirebaseFirestore.instance;
      final areaRef = firestore.collection('areas').doc('$division-$areaName');
      final showRef = firestore.collection('user_accounts_show').doc('$division-$areaName');
      trace.log(
        '지역 스키마 확인: division=$division area=$areaName modes=${result.settings.modeKeys.join(',')} capabilities=${result.settings.capabilityKeys.join(',')} thirdPartyFields=excluded limits=${result.settings.activeLimit ?? 'unset'}/${result.settings.totalLimit ?? 'unset'}',
        progress: 0.16,
      );
      await firestore.runTransaction((transaction) async {
        final areaSnap = await transaction.get(areaRef);
        final showSnap = await transaction.get(showRef);
        if (areaSnap.exists) throw StateError('AREA_ALREADY_EXISTS');
        if (showSnap.exists) throw StateError('AREA_ACCOUNT_META_ALREADY_EXISTS');
        trace.log('중복 문서 검사 완료: reads=2', progress: 0.4);
        transaction.set(
          areaRef,
          result.settings.areaPayload(
            name: areaName,
            division: division,
            isHeadquarter: false,
          ),
        );
        transaction.set(
          showRef,
          result.settings.accountMetaPayload(
            division: division,
            area: areaName,
            activeCount: 0,
            inactiveCount: 0,
          ),
        );
      });
      trace.log('Firestore transaction commit 완료: writes=2', progress: 0.9);
      _refreshAreas();
      await trace.succeed('지역과 계정 메타 생성이 완료되었습니다.');
      if (!mounted) return;
      if (!trace.developerMode) {
        showSuccessSnackbar(
          context,
          '"$areaName" 지역이 생성되었습니다.',
          useCommonUi: true,
        );
      }
    } catch (error, stackTrace) {
      await trace.fail(
        '지역 생성에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      final raw = error.toString();
      final message = raw.contains('AREA_ALREADY_EXISTS')
          ? '이미 존재하는 지역입니다.'
          : raw.contains('AREA_ACCOUNT_META_ALREADY_EXISTS')
              ? '동일한 지역 계정 메타가 이미 존재합니다.'
              : '지역 생성 실패: $error';
      showFailedSnackbar(context, message, useCommonUi: true);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _openEditDialog(DevAreaListItem item) async {
    if (_mutating) return;
    setState(() => _editingAreaId = item.documentId);
    int? activeLimit;
    int? totalLimit;
    try {
      final meta = await FirebaseFirestore.instance
          .collection('user_accounts_show')
          .doc('${item.division}-${item.name}')
          .get(const GetOptions(source: Source.serverAndCache));
      final data = meta.data() ?? <String, dynamic>{};
      activeLimit = data['activeLimit'] is int ? data['activeLimit'] as int : null;
      totalLimit = data['totalLimit'] is int ? data['totalLimit'] as int : null;
    } catch (error, stackTrace) {
      if (mounted) setState(() => _editingAreaId = null);
      if (!mounted) return;
      final trace = await DeveloperOperationTrace.start(
        context: context,
        title: '지역 설정 불러오기',
        initialMessage: '지역 계정 정책을 불러오지 못해 수정 화면을 열지 않습니다.',
        useCommonUi: true,
        developerModeMessage: '개발자 모드 ON: 지역 설정 조회 실패 로그를 debugPrint 코드로 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF: 지역 설정 조회 실패 로그를 콘솔에 기록합니다.',
      );
      trace.log(
        '계정 정책 조회 실패: division=${item.division} area=${item.name} existingLimitPreserved=true',
        progress: 0.35,
      );
      await trace.fail(
        '계정 정책을 확인하지 못해 기존 리밋을 보호하기 위해 지역 수정을 중단했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      await StatusDialog.showFailure(
        context,
        title: '지역 설정을 불러오지 못했습니다',
        description: '기존 계정 리밋을 보호하기 위해 수정 화면을 열지 않았습니다. 네트워크 상태를 확인한 뒤 다시 시도하세요.',
        useCommonUi: true,
      );
      return;
    }
    if (!mounted) return;
    final result = await showCommonOverlayDialog<_AreaEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AreaEditorDialog(
        division: item.division,
        isEdit: true,
        initial: item,
        initialActiveLimit: activeLimit,
        initialTotalLimit: totalLimit,
      ),
    );
    if (!mounted) return;
    setState(() => _editingAreaId = null);
    if (result == null) return;
    await _updateArea(item, result.settings);
  }

  Future<void> _updateArea(DevAreaListItem item, DevAreaSettingsDraft settings) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '지역 설정 수정',
      initialMessage: '지역 최신 스키마 저장을 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 지역 수정 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 지역 수정 로그를 콘솔에 기록합니다.',
    );
    try {
      final firestore = FirebaseFirestore.instance;
      final areaRef = firestore.collection('areas').doc(item.documentId);
      final showRef = firestore.collection('user_accounts_show').doc('${item.division}-${item.name}');
      trace.log(
        '저장 필드 확인: englishName=${settings.englishName} modes=${item.isHeadquarter ? DevAreaModePolicy.canonicalModes.join(',') : settings.modeKeys.join(',')} capabilities=${settings.capabilityKeys.join(',')} thirdPartyFields=preserved-not-written isHeadquarter=${item.isHeadquarter}',
        progress: 0.2,
      );
      if (!item.hasCanonicalModes) {
        trace.log(
          'legacy mode 정규화: source=${item.modes.join(',')} target=${item.isHeadquarter ? DevAreaModePolicy.canonicalModes.join(',') : settings.modeKeys.join(',')}',
          progress: 0.28,
        );
      }
      await firestore.runTransaction((transaction) async {
        final areaSnap = await transaction.get(areaRef);
        if (!areaSnap.exists) throw StateError('AREA_NOT_FOUND');
        transaction.update(
          areaRef,
          item.isHeadquarter
              ? settings.headquarterAreaPayload(
                  name: item.name,
                  division: item.division,
                  includeCreatedAt: false,
                )
              : settings.areaPayload(
                  name: item.name,
                  division: item.division,
                  isHeadquarter: false,
                  includeCreatedAt: false,
                ),
        );
        transaction.set(
          showRef,
          <String, dynamic>{
            'division': item.division,
            'area': item.name,
            if (settings.activeLimit != null) 'activeLimit': settings.activeLimit,
            if (settings.totalLimit != null) 'totalLimit': settings.totalLimit,
            if (settings.activeLimit == null) 'activeLimit': FieldValue.delete(),
            if (settings.totalLimit == null) 'totalLimit': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      trace.log('Area 최신 필드와 계정 정책 저장 완료', progress: 0.9);
      _refreshAreas();
      await trace.succeed('지역 설정 수정이 완료되었습니다.');
      if (!mounted) return;
      if (!trace.developerMode) {
        showSuccessSnackbar(
          context,
          '"${item.name}" 지역 설정이 저장되었습니다.',
          useCommonUi: true,
        );
      }
    } catch (error, stackTrace) {
      await trace.fail(
        '지역 설정 수정에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      showFailedSnackbar(
        context,
        '지역 설정 저장 실패: $error',
        useCommonUi: true,
      );
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _deleteArea(DevAreaListItem item) async {
    if (_mutating || _deletingAreaName != null) return;
    final confirm = await showOpsConfirmDialog(
      context: context,
      title: '지역 삭제',
      message: '"${item.name}" 지역과 비어 있는 계정 메타를 삭제합니다. 계정이 남아 있으면 삭제하지 않습니다.',
      confirmLabel: '삭제',
      icon: Icons.location_off_rounded,
      destructive: true,
    );
    if (!confirm || !mounted) return;
    setState(() => _deletingAreaName = item.name);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '지역 삭제',
      initialMessage: '지역 삭제 전 계정 연관성을 확인합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 지역 삭제 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 지역 삭제 로그를 콘솔에 기록합니다.',
    );
    try {
      final firestore = FirebaseFirestore.instance;
      final showRef = firestore.collection('user_accounts_show').doc('${item.division}-${item.name}');
      final projectionSnap = await showRef
          .collection('users')
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (projectionSnap.docs.isNotEmpty) {
        throw StateError('RELATED_USER_PROJECTION_EXISTS');
      }
      final accountCandidates = await firestore
          .collection('user_accounts')
          .where('areas', arrayContains: item.name)
          .get(const GetOptions(source: Source.server));
      final accountExists = accountCandidates.docs.any((doc) {
        final divisions = List<dynamic>.from(doc.data()['divisions'] ?? const <dynamic>[])
            .map((value) => value.toString().trim())
            .toSet();
        return divisions.contains(item.division);
      });
      trace.log(
        '연관 계정 검사 완료: projectionExists=${projectionSnap.docs.isNotEmpty} sourceCandidates=${accountCandidates.docs.length} sourceMatch=$accountExists',
        progress: 0.42,
      );
      if (accountExists) throw StateError('RELATED_USER_ACCOUNT_EXISTS');
      final batch = firestore.batch();
      batch.delete(firestore.collection('areas').doc(item.documentId));
      batch.delete(showRef);
      await batch.commit();
      trace.log('Area 및 계정 메타 삭제 commit 완료: writes=2', progress: 0.9);
      _refreshAreas();
      await trace.succeed('지역 삭제가 완료되었습니다.');
      if (!mounted) return;
      if (!trace.developerMode) {
        showSuccessSnackbar(
          context,
          '"${item.name}" 지역이 삭제되었습니다.',
          useCommonUi: true,
        );
      }
    } catch (error, stackTrace) {
      await trace.fail(
        '지역 삭제에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      final raw = error.toString();
      final message = raw.contains('RELATED_USER')
          ? '소속 계정이 남아 있어 지역을 삭제할 수 없습니다.'
          : '지역 삭제 실패: $error';
      showFailedSnackbar(context, message, useCommonUi: true);
    } finally {
      if (mounted) setState(() => _deletingAreaName = null);
    }
  }

  Widget _buildScopeSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockListSurface(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DropdownButtonFormField<String>(
          value: widget.divisionList.contains(widget.selectedDivision) ? widget.selectedDivision : null,
          isExpanded: true,
          items: widget.divisionList
              .map(
                (division) => DropdownMenuItem<String>(
                  value: division,
                  child: Text(
                    division,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: _mutating
              ? null
              : (value) {
                  widget.onDivisionChanged(value);
                  setState(() {
                    _editingAreaId = null;
                    _areasFuture = _loadAreas();
                  });
                },
          decoration: opsInputDecoration(
            context,
            label: '회사 선택',
            prefixIcon: Icon(Icons.business_rounded, color: tokens.iconSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildAddSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final enabled = widget.selectedDivision != null && !_mutating && _deletingAreaName == null;
    return OpsDockListSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 9, 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.add_location_alt_rounded,
                size: 19,
                color: tokens.onAccentContainer,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '지역 추가',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.selectedDivision == null
                        ? '회사를 먼저 선택하세요.'
                        : '${widget.selectedDivision}에 최신 Area 스키마를 생성합니다.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CommonIconButton(
              icon: Icons.add_rounded,
              tooltip: '지역 추가',
              onPressed: enabled ? _openCreateDialog : null,
              haptic: CommonHaptic.selection,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAreaRow(BuildContext context, DevAreaListItem item, int index) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final deleting = _deletingAreaName == item.name;
    final editing = _editingAreaId == item.documentId;
    final modeText = item.modes.isEmpty
        ? '운영 모드 미설정'
        : item.modes.map(DevAreaModePolicy.label).join(' · ');
    final capText = item.capabilities.isEmpty ? '기능 없음' : Cap.human(item.capabilities);
    final schemaText = item.schemaComplete ? '최신 스키마' : '스키마 보완 필요';
    final schemaColor = item.schemaComplete ? tokens.success : tokens.warning;
    return CommonAnimatedReveal(
      delay: reduceMotion ? Duration.zero : Duration(milliseconds: index * 24),
      offset: const Offset(.018, 0),
      child: AnimatedOpacity(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        opacity: deleting ? .58 : 1,
        child: OpsDockSelectableRowSurface(
          selected: editing,
          selectionColor: tokens.accent,
          selectedContainer: tokens.accentContainer,
          onTap: _mutating || deleting ? () {} : () => _openEditDialog(item),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: item.isHeadquarter ? tokens.warningContainer : tokens.surfaceSelected,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                ),
                alignment: Alignment.center,
                child: Icon(
                  item.isHeadquarter ? Icons.apartment_rounded : Icons.location_on_rounded,
                  size: 20,
                  color: item.isHeadquarter ? tokens.warning : tokens.iconSecondary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedSwitcher(
                          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                          child: Text(
                            schemaText,
                            key: ValueKey<String>('${item.documentId}_${item.schemaComplete}'),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: schemaColor,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.englishName.isEmpty ? '영문명 미설정' : item.englishName} · $modeText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      capText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CommonIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: item.isHeadquarter ? '본사는 회사 관리에서 삭제' : '지역 삭제',
                destructive: true,
                loading: deleting,
                onPressed: item.isHeadquarter || _mutating || _deletingAreaName != null
                    ? null
                    : () => _deleteArea(item),
                haptic: CommonHaptic.medium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAreaList(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final division = widget.selectedDivision;
    if (division == null) {
      return const OpsDockListSurface(
        child: SizedBox(
          height: 280,
          child: OpsEmptyState(
            icon: Icons.business_rounded,
            title: '회사를 선택하세요',
            message: '선택한 회사의 지역을 List Surface에서 관리할 수 있습니다.',
          ),
        ),
      );
    }
    return OpsDockListSurface(
      child: FutureBuilder<List<DevAreaListItem>>(
        future: _areasFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 280,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return SizedBox(
              height: 280,
              child: OpsEmptyState(
                icon: Icons.error_outline_rounded,
                title: '지역 목록을 불러오지 못했습니다',
                message: snapshot.error.toString(),
              ),
            );
          }
          final areas = snapshot.data ?? const <DevAreaListItem>[];
          if (areas.isEmpty) {
            return const SizedBox(
              height: 280,
              child: OpsEmptyState(
                icon: Icons.location_off_rounded,
                title: '등록된 지역이 없습니다',
                message: '지역 추가에서 첫 지역을 등록하세요.',
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: areas.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              thickness: 1,
              color: tokens.borderSubtle,
            ),
            itemBuilder: (context, index) => _buildAreaRow(context, areas[index], index),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return ColoredBox(
      color: tokens.canvas,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommonAnimatedReveal(child: _buildScopeSurface(context)),
            const SizedBox(height: 9),
            CommonAnimatedReveal(
              delay: const Duration(milliseconds: 35),
              child: _buildAddSurface(context),
            ),
            const SizedBox(height: 9),
            Expanded(child: _buildAreaList(context)),
          ],
        ),
      ),
    );
  }
}

class _AreaEditorResult {
  const _AreaEditorResult({
    required this.name,
    required this.settings,
  });

  final String name;
  final DevAreaSettingsDraft settings;
}

class _AreaEditorDialog extends StatefulWidget {
  const _AreaEditorDialog({
    required this.division,
    required this.isEdit,
    this.initial,
    this.initialActiveLimit,
    this.initialTotalLimit,
  });

  final String division;
  final bool isEdit;
  final DevAreaListItem? initial;
  final int? initialActiveLimit;
  final int? initialTotalLimit;

  @override
  State<_AreaEditorDialog> createState() => _AreaEditorDialogState();
}

class _AreaEditorDialogState extends State<_AreaEditorDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _divisionController = TextEditingController();
  final TextEditingController _englishController = TextEditingController();
  final TextEditingController _activeLimitController = TextEditingController();
  final TextEditingController _totalLimitController = TextEditingController();

  Set<String> _modes = <String>{};
  Set<Capability> _capabilities = <Capability>{};
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _divisionController.text = widget.division;
    final initial = widget.initial;
    if (initial != null) {
      _nameController.text = initial.name;
      _englishController.text = initial.englishName;
      _modes = initial.isHeadquarter
          ? Set<String>.of(DevAreaModePolicy.headquarterModes)
          : DevAreaModePolicy.normalizeModes(initial.modes);
      _capabilities = Set<Capability>.of(initial.capabilities);
    }
    if (widget.initialActiveLimit != null) {
      _activeLimitController.text = widget.initialActiveLimit.toString();
    }
    if (widget.initialTotalLimit != null) {
      _totalLimitController.text = widget.initialTotalLimit.toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _divisionController.dispose();
    _englishController.dispose();
    _activeLimitController.dispose();
    _totalLimitController.dispose();
    super.dispose();
  }

  void _submit() {
    final areaName = DevManagementValidation.normalizeName(_nameController.text);
    if (areaName.isEmpty) {
      setState(() => _errorText = '지역 이름을 입력하세요.');
      return;
    }
    final settingsError = DevManagementValidation.validateAreaSettings(
      englishName: _englishController.text,
      modes: _modes,
      activeLimit: _activeLimitController.text,
      totalLimit: _totalLimitController.text,
    );
    if (settingsError != null) {
      setState(() => _errorText = settingsError);
      return;
    }
    final activeLimit = DevManagementValidation.parseOptionalLimit(_activeLimitController.text);
    final totalLimit = DevManagementValidation.parseOptionalLimit(_totalLimitController.text);
    Navigator.of(context).pop(
      _AreaEditorResult(
        name: areaName,
        settings: DevAreaSettingsDraft(
          englishName: _englishController.text.trim(),
          modes: Set<String>.of(_modes),
          capabilities: Set<Capability>.of(_capabilities),
          activeLimit: activeLimit,
          totalLimit: totalLimit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final initial = widget.initial;
    return AlertDialog(
      title: Text(widget.isEdit ? '지역 설정' : '지역 추가'),
      content: SizedBox(
        width: 590,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.enter,
                child: AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  child: _errorText == null
                      ? const SizedBox.shrink(key: ValueKey<String>('area_error_none'))
                      : Container(
                          key: ValueKey<String>(_errorText!),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: tokens.dangerContainer,
                            borderRadius: BorderRadius.circular(CommonUiShapes.control),
                            border: Border.all(color: tokens.danger),
                          ),
                          child: Text(
                            _errorText!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: tokens.onDangerContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                ),
              ),
              OpsDockListSurface(
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nameController,
                        enabled: !widget.isEdit,
                        autofocus: !widget.isEdit,
                        textInputAction: TextInputAction.next,
                        decoration: opsInputDecoration(
                          context,
                          label: '지역 이름',
                          prefixIcon: Icon(
                            initial?.isHeadquarter == true ? Icons.apartment_rounded : Icons.location_city_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _divisionController,
                        readOnly: true,
                        decoration: opsInputDecoration(
                          context,
                          label: '회사',
                          prefixIcon: const Icon(Icons.business_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DevAreaSettingsFields(
                        englishNameController: _englishController,
                        activeLimitController: _activeLimitController,
                        totalLimitController: _totalLimitController,
                        selectedModes: _modes,
                        selectedCapabilities: _capabilities,
                        showModeSelector: initial?.isHeadquarter != true,
                        onModesChanged: (value) => setState(() {
                          _errorText = null;
                          _modes = value;
                        }),
                        onCapabilitiesChanged: (value) => setState(() {
                          _errorText = null;
                          _capabilities = value;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: Icon(widget.isEdit ? Icons.save_rounded : Icons.add_location_alt_rounded),
          label: Text(widget.isEdit ? '저장' : '생성'),
        ),
      ],
    );
  }
}
