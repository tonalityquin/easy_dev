import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../widgets/ops_console_dialogs.dart';
import '../../../widgets/ops_console_widgets.dart';

class DivisionManagementTab extends StatefulWidget {
  final List<String> divisionList;
  final Future<void> Function(String) onDivisionAdded;
  final Future<void> Function(String) onDivisionDeleted;

  const DivisionManagementTab({
    super.key,
    required this.divisionList,
    required this.onDivisionAdded,
    required this.onDivisionDeleted,
  });

  @override
  State<DivisionManagementTab> createState() => _DivisionManagementTabState();
}

class _DivisionManagementTabState extends State<DivisionManagementTab> {
  final TextEditingController _controller = TextEditingController();
  bool _adding = false;
  String? _deletingDivisionName;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleAddDivision() async {
    if (_adding) return;
    final input = _controller.text.trim();
    if (input.isEmpty) {
      showSelectedSnackbar(
        context,
        '회사 이름을 입력해주세요.',
        usePromptUi: true,
      );
      return;
    }
    if (input.contains('/')) {
      showSelectedSnackbar(
        context,
        '회사 이름에 "/" 문자는 사용할 수 없습니다.',
        usePromptUi: true,
      );
      return;
    }

    setState(() => _adding = true);
    try {
      await widget.onDivisionAdded(input);
      await FirebaseFirestore.instance.collection('areas').doc('$input-$input').set({
        'name': input,
        'division': input,
        'isHeadquarter': true,
        'modes': const <String>['service', 'lite'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _controller.clear();
      FocusScope.of(context).unfocus();
      showSuccessSnackbar(
        context,
        '회사 "$input"이 추가되었습니다.',
        usePromptUi: true,
      );
    } catch (error) {
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '회사 추가 실패: $error',
        usePromptUi: true,
      );
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  Future<void> _handleDeleteDivision(String division) async {
    if (_deletingDivisionName != null) {
      showSelectedSnackbar(
        context,
        '다른 삭제 작업이 진행 중입니다.',
        usePromptUi: true,
      );
      return;
    }
    final ok = await showOpsConfirmDialog(
      context: context,
      title: '회사 삭제',
      message: '"$division" 회사와 소속 지역을 모두 삭제하시겠습니까?',
      confirmLabel: '삭제',
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deletingDivisionName = division);
    try {
      await widget.onDivisionDeleted(division);
    } catch (error) {
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '삭제 실패: $error',
        usePromptUi: true,
      );
    } finally {
      if (mounted) {
        setState(() => _deletingDivisionName = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _adding || _deletingDivisionName != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OpsWorkSection(
          title: '회사 등록',
          subtitle: '새 회사를 추가하면 본사 지역 문서도 함께 생성합니다.',
          icon: Icons.add_business_rounded,
          child: Column(
            children: [
              TextField(
                controller: _controller,
                enabled: !busy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleAddDivision(),
                decoration: opsInputDecoration(
                  context,
                  label: '회사 이름',
                  prefixIcon: const Icon(Icons.business_rounded),
                ),
              ),
              const SizedBox(height: 14),
              OpsActionButton(
                label: _adding ? '회사 추가 중' : '회사 추가',
                icon: Icons.add_business_rounded,
                onPressed: busy ? null : _handleAddDivision,
              ),
            ],
          ),
        ),
        OpsWorkSection(
          title: '등록된 회사',
          subtitle: '회사 삭제 시 소속 지역도 함께 제거됩니다.',
          icon: Icons.business_center_rounded,
          child: SizedBox(
            height: 420,
            child: widget.divisionList.isEmpty
                ? const OpsEmptyState(
                    icon: Icons.business_outlined,
                    title: '등록된 회사가 없습니다',
                    message: '상단 양식에서 첫 회사를 등록하세요.',
                  )
                : ListView.separated(
                    itemCount: widget.divisionList.length,
                    separatorBuilder: (_, __) => const OpsDivider(),
                    itemBuilder: (context, index) {
                      final division = widget.divisionList[index];
                      final deleting = _deletingDivisionName == division;
                      return PromptAnimatedReveal(
                        delay: Duration(milliseconds: index * 30),
                        offset: const Offset(.02, 0),
                        child: ListTile(
                          leading: const Icon(Icons.business_rounded),
                          title: Text(division),
                          trailing: PromptIconButton(
                            icon: Icons.delete_outline_rounded,
                            tooltip: '회사 삭제',
                            destructive: true,
                            loading: deleting,
                            onPressed: busy
                                ? null
                                : () => _handleDeleteDivision(division),
                            haptic: PromptHaptic.medium,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
