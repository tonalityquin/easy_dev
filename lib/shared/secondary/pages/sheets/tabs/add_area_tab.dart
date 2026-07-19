import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../widgets/ops_console_dialogs.dart';
import '../../../widgets/ops_console_widgets.dart';

class AddAreaTab extends StatefulWidget {
  final String? selectedDivision;
  final List<String> divisionList;
  final ValueChanged<String?> onDivisionChanged;

  const AddAreaTab({
    super.key,
    required this.selectedDivision,
    required this.divisionList,
    required this.onDivisionChanged,
  });

  @override
  State<AddAreaTab> createState() => _AddAreaTabState();
}

class _AddAreaTabState extends State<AddAreaTab> {
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _englishAreaController = TextEditingController();
  bool _adding = false;
  String? _deletingAreaName;
  Future<List<String>>? _areasFuture;
  String _selectedModeKey = 'service';

  static const List<_ModeItem> _modeItems = <_ModeItem>[
    _ModeItem(key: 'service', label: '서비스 모드'),
    _ModeItem(key: 'lite', label: 'Lite 모드'),
    _ModeItem(key: 'both', label: '공용(서비스+Lite)'),
  ];

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
    }
  }

  @override
  void dispose() {
    _areaController.dispose();
    _englishAreaController.dispose();
    super.dispose();
  }

  String _normalize(String value) {
    return value.trim().replaceAll('/', '-').replaceAll(RegExp(r'\s+'), ' ');
  }

  List<String> _toModes(String key) {
    switch (key) {
      case 'lite':
        return const <String>['lite'];
      case 'both':
        return const <String>['service', 'lite'];
      default:
        return const <String>['service'];
    }
  }

  Future<void> _addArea() async {
    if (_adding) return;
    final areaName = _normalize(_areaController.text);
    final englishAreaName = _englishAreaController.text.trim();
    final division = widget.selectedDivision;
    if (division == null || division.isEmpty) {
      showFailedSnackbar(
        context,
        '먼저 회사를 선택하세요.',
        usePromptUi: true,
      );
      return;
    }
    if (areaName.isEmpty) {
      showFailedSnackbar(
        context,
        '새 지역 이름을 입력하세요.',
        usePromptUi: true,
      );
      return;
    }

    setState(() => _adding = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final reference = firestore.collection('areas').doc('$division-$areaName');
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (snapshot.exists) {
          throw Exception('이미 존재하는 지역입니다.');
        }
        transaction.set(reference, {
          'name': areaName,
          'englishName': englishAreaName,
          'division': division,
          'modes': _toModes(_selectedModeKey),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      if (!mounted) return;
      _areaController.clear();
      _englishAreaController.clear();
      FocusScope.of(context).unfocus();
      setState(() => _areasFuture = _loadAreas());
      showSuccessSnackbar(
        context,
        '"$areaName" 지역이 추가되었습니다.',
        usePromptUi: true,
      );
    } catch (error) {
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '지역 추가 실패: $error',
        usePromptUi: true,
      );
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  Future<List<String>> _loadAreas() async {
    final division = widget.selectedDivision;
    if (division == null || division.isEmpty) return const <String>[];
    final snapshot = await FirebaseFirestore.instance
        .collection('areas')
        .where('division', isEqualTo: division)
        .get(const GetOptions(source: Source.serverAndCache));
    final list = snapshot.docs
        .map((doc) => (doc['name'] as String?)?.trim())
        .whereType<String>()
        .toList()
      ..sort();
    return list;
  }

  Future<void> _deleteArea(String areaName) async {
    if (_deletingAreaName != null) {
      showSelectedSnackbar(
        context,
        '다른 삭제 작업이 진행 중입니다.',
        usePromptUi: true,
      );
      return;
    }
    final division = widget.selectedDivision;
    if (division == null || division.isEmpty) return;
    final confirm = await showOpsConfirmDialog(
      context: context,
      title: '지역 삭제',
      message: '"$areaName" 지역을 삭제하시겠습니까?',
      confirmLabel: '삭제',
      icon: Icons.location_off_rounded,
      destructive: true,
    );
    if (!confirm || !mounted) return;

    setState(() => _deletingAreaName = areaName);
    try {
      await FirebaseFirestore.instance
          .collection('areas')
          .doc('$division-$areaName')
          .delete();
      if (!mounted) return;
      setState(() => _areasFuture = _loadAreas());
      showSuccessSnackbar(
        context,
        '"$areaName" 지역이 삭제되었습니다.',
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
        setState(() => _deletingAreaName = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _adding || _deletingAreaName != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OpsWorkSection(
          title: '지역 정보',
          subtitle: '회사와 운영 모드를 선택하고 새 지역을 등록합니다.',
          icon: Icons.add_location_alt_rounded,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: widget.selectedDivision,
                items: widget.divisionList
                    .map(
                      (division) => DropdownMenuItem<String>(
                        value: division,
                        child: Text(division),
                      ),
                    )
                    .toList(growable: false),
                onChanged: busy
                    ? null
                    : (value) {
                        widget.onDivisionChanged(value);
                        setState(() => _areasFuture = _loadAreas());
                      },
                decoration: opsInputDecoration(
                  context,
                  label: '회사 선택',
                  prefixIcon: const Icon(Icons.business_rounded),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedModeKey,
                items: _modeItems
                    .map(
                      (mode) => DropdownMenuItem<String>(
                        value: mode.key,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() => _selectedModeKey = value ?? 'service');
                      },
                decoration: opsInputDecoration(
                  context,
                  label: '운영 모드',
                  prefixIcon: const Icon(Icons.widgets_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _areaController,
                textInputAction: TextInputAction.next,
                enabled: !busy,
                decoration: opsInputDecoration(
                  context,
                  label: '지역 이름',
                  prefixIcon: const Icon(Icons.location_city_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _englishAreaController,
                textInputAction: TextInputAction.done,
                enabled: !busy,
                onSubmitted: (_) => _addArea(),
                decoration: opsInputDecoration(
                  context,
                  label: '영문 지역 이름',
                  prefixIcon: const Icon(Icons.translate_rounded),
                ),
              ),
              const SizedBox(height: 14),
              OpsActionButton(
                label: _adding ? '지역 추가 중' : '지역 추가',
                icon: Icons.add_location_alt_rounded,
                onPressed: busy ? null : _addArea,
              ),
            ],
          ),
        ),
        OpsWorkSection(
          title: '등록된 지역',
          subtitle: widget.selectedDivision == null
              ? '회사를 선택하면 지역 목록을 확인할 수 있습니다.'
              : '${widget.selectedDivision} 소속 지역입니다.',
          icon: Icons.list_alt_rounded,
          child: SizedBox(
            height: 360,
            child: widget.selectedDivision == null
                ? const OpsEmptyState(
                    icon: Icons.business_rounded,
                    title: '회사를 선택하세요',
                    message: '상단 회사 선택에서 관리할 회사를 지정하세요.',
                  )
                : FutureBuilder<List<String>>(
                    future: _areasFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final areas = snapshot.data ?? const <String>[];
                      if (areas.isEmpty) {
                        return const OpsEmptyState(
                          icon: Icons.location_off_rounded,
                          title: '등록된 지역이 없습니다',
                          message: '상단 양식에서 첫 지역을 등록하세요.',
                        );
                      }
                      return ListView.separated(
                        itemCount: areas.length,
                        separatorBuilder: (_, __) => const OpsDivider(),
                        itemBuilder: (context, index) {
                          final areaName = areas[index];
                          final deleting = _deletingAreaName == areaName;
                          return PromptAnimatedReveal(
                            delay: Duration(milliseconds: index * 30),
                            offset: const Offset(.02, 0),
                            child: ListTile(
                              key: ValueKey<String>(areaName),
                              leading: const Icon(Icons.location_on_rounded),
                              title: Text(areaName),
                              trailing: PromptIconButton(
                                icon: Icons.delete_outline_rounded,
                                tooltip: '지역 삭제',
                                destructive: true,
                                loading: deleting,
                                onPressed: busy
                                    ? null
                                    : () => _deleteArea(areaName),
                                haptic: PromptHaptic.medium,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _ModeItem {
  final String key;
  final String label;

  const _ModeItem({required this.key, required this.label});
}
