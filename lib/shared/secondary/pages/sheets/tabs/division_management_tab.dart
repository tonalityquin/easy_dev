import 'package:flutter/material.dart';

import '../../../../../app/models/capability.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../widgets/ops_console_dialogs.dart';
import '../../../widgets/ops_console_widgets.dart';
import 'dev_management_common.dart';

class DivisionManagementTab extends StatefulWidget {
  const DivisionManagementTab({
    super.key,
    required this.divisionList,
    required this.onDivisionAdded,
    required this.onDivisionDeleted,
  });

  final List<String> divisionList;
  final Future<bool> Function(DivisionCreateRequest) onDivisionAdded;
  final Future<bool> Function(String) onDivisionDeleted;

  @override
  State<DivisionManagementTab> createState() => _DivisionManagementTabState();
}

class _DivisionManagementTabState extends State<DivisionManagementTab> {
  bool _adding = false;
  String? _deletingDivisionName;

  Future<void> _openCreateDialog() async {
    if (_adding || _deletingDivisionName != null) return;
    final request = await showCommonOverlayDialog<DivisionCreateRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DivisionCreateDialog(),
    );
    if (request == null || !mounted) return;
    setState(() => _adding = true);
    final success = await widget.onDivisionAdded(request);
    if (!mounted) return;
    setState(() => _adding = false);
    if (success) {
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _handleDeleteDivision(String division) async {
    if (_adding || _deletingDivisionName != null) return;
    final ok = await showOpsConfirmDialog(
      context: context,
      title: '회사 삭제',
      message: '"$division" 회사와 소속 지역, 비어 있는 계정 메타 문서를 삭제합니다. 계정이나 운영 데이터가 남아 있으면 먼저 정리해야 합니다.',
      confirmLabel: '삭제',
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deletingDivisionName = division);
    await widget.onDivisionDeleted(division);
    if (!mounted) return;
    setState(() => _deletingDivisionName = null);
  }

  Widget _buildCreateSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final busy = _adding || _deletingDivisionName != null;
    return OpsDockListSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 11, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.add_business_rounded,
                size: 20,
                color: tokens.onAccentContainer,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '회사 추가',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '회사와 본사 지역, 계정 메타를 함께 생성합니다.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          height: 1.3,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : CommonUiMotion.selection,
              child: _adding
                  ? SizedBox(
                      key: const ValueKey<String>('division_adding'),
                      width: 32,
                      height: 32,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: tokens.accent,
                        ),
                      ),
                    )
                  : CommonIconButton(
                      key: const ValueKey<String>('division_add'),
                      icon: Icons.add_rounded,
                      tooltip: '회사 추가',
                      onPressed: busy ? null : _openCreateDialog,
                      haptic: CommonHaptic.selection,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivisionList(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.divisionList.isEmpty) {
      return const OpsDockListSurface(
        child: SizedBox(
          height: 260,
          child: OpsEmptyState(
            icon: Icons.business_outlined,
            title: '등록된 회사가 없습니다',
            message: '회사 추가에서 첫 회사를 등록하세요.',
          ),
        ),
      );
    }

    return OpsDockListSurface(
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        child: ListView.separated(
          key: ValueKey<String>('division_list_${widget.divisionList.join('|')}'),
          padding: EdgeInsets.zero,
          itemCount: widget.divisionList.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            thickness: 1,
            color: tokens.borderSubtle,
          ),
          itemBuilder: (context, index) {
            final division = widget.divisionList[index];
            final deleting = _deletingDivisionName == division;
            return CommonAnimatedReveal(
              delay: reduceMotion ? Duration.zero : Duration(milliseconds: index * 24),
              offset: const Offset(.018, 0),
              child: AnimatedOpacity(
                duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                opacity: deleting ? .62 : 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 9, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: tokens.surfaceSelected,
                          borderRadius: BorderRadius.circular(CommonUiShapes.control),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.business_rounded,
                          size: 19,
                          color: tokens.iconSecondary,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              division,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '본사 지역 포함 · 상세 설정은 지역 탭에서 관리',
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
                        icon: Icons.delete_outline_rounded,
                        tooltip: '회사 삭제',
                        destructive: true,
                        loading: deleting,
                        onPressed: _adding || _deletingDivisionName != null
                            ? null
                            : () => _handleDeleteDivision(division),
                        haptic: CommonHaptic.medium,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
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
            CommonAnimatedReveal(child: _buildCreateSurface(context)),
            const SizedBox(height: 10),
            Expanded(child: _buildDivisionList(context)),
          ],
        ),
      ),
    );
  }
}

class _DivisionCreateDialog extends StatefulWidget {
  const _DivisionCreateDialog();

  @override
  State<_DivisionCreateDialog> createState() => _DivisionCreateDialogState();
}

class _DivisionCreateDialogState extends State<_DivisionCreateDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _englishController = TextEditingController();
  final TextEditingController _activeLimitController = TextEditingController();
  final TextEditingController _totalLimitController = TextEditingController();

  Set<Capability> _capabilities = <Capability>{};
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _englishController.dispose();
    _activeLimitController.dispose();
    _totalLimitController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '회사 이름을 입력하세요.');
      return;
    }
    if (name.contains('/')) {
      setState(() => _errorText = '회사 이름에 "/" 문자는 사용할 수 없습니다.');
      return;
    }
    final settingsError = DevManagementValidation.validateAreaSettings(
      englishName: _englishController.text,
      modes: DevAreaModePolicy.headquarterModes,
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
      DivisionCreateRequest(
        name: name,
        settings: DevAreaSettingsDraft(
          englishName: _englishController.text.trim(),
          modes: Set<String>.of(DevAreaModePolicy.headquarterModes),
          capabilities: Set<Capability>.of(_capabilities),
          activeLimit: activeLimit,
          totalLimit: totalLimit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tokens = CommonUiTheme.of(context);
    return AlertDialog(
      title: const Text('회사 추가'),
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
                      ? const SizedBox.shrink(key: ValueKey<String>('division_error_none'))
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
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (_errorText != null) setState(() => _errorText = null);
                        },
                        decoration: opsInputDecoration(
                          context,
                          label: '회사 이름',
                          prefixIcon: const Icon(Icons.business_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DevAreaSettingsFields(
                        englishNameController: _englishController,
                        activeLimitController: _activeLimitController,
                        totalLimitController: _totalLimitController,
                        selectedModes: DevAreaModePolicy.headquarterModes,
                        selectedCapabilities: _capabilities,
                        showModeSelector: false,
                        onModesChanged: (_) {},
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
          icon: const Icon(Icons.add_business_rounded),
          label: const Text('생성'),
        ),
      ],
    );
  }
}
