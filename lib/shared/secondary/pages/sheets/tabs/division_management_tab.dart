import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../../app/usage/usage_reporter.dart';
import '../../../../../app/utils/snackbar_helper.dart';

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
      showSelectedSnackbar(context, '회사 이름을 입력해주세요.');
      return;
    }

    if (input.contains('/')) {
      showSelectedSnackbar(context, '회사 이름에 "/" 문자는 사용할 수 없습니다.');
      return;
    }

    setState(() => _adding = true);
    try {
      await widget.onDivisionAdded(input);

      try {
        await UsageReporter.instance.report(
          area: input,
          action: 'write',
          n: 1,
          source: 'DivisionManagementTab.addDivision.divisions.callback',
        );
      } catch (_) {}

      final areaId = '$input-$input';
      await FirebaseFirestore.instance.collection('areas').doc(areaId).set({
        'name': input,
        'division': input,
        'isHeadquarter': true,
        'modes': const ['service', 'lite'],
        'createdAt': FieldValue.serverTimestamp(),
      });

      try {
        await UsageReporter.instance.report(
          area: input,
          action: 'write',
          n: 1,
          source: 'DivisionManagementTab.addDivision.areas.headquarter.set',
        );
      } catch (_) {}

      if (!mounted) return;
      _controller.clear();
      FocusScope.of(context).unfocus();

      showSuccessSnackbar(context, '회사 "$input" 이(가) 추가되었습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '회사 추가 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  Future<void> _handleDeleteDivision(String division) async {
    if (_deletingDivisionName != null) {
      if (!mounted) return;
      showSelectedSnackbar(context, '다른 삭제 작업이 진행 중입니다. 잠시만 기다려주세요.');
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('회사 삭제'),
            content: Text('"$division" 회사와 소속 지역을 모두 삭제하시겠습니까?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('취소')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('삭제')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    if (!mounted) return;
    setState(() => _deletingDivisionName = division);

    try {
      await widget.onDivisionDeleted(division);

      try {
        await UsageReporter.instance.report(
          area: division,
          action: 'delete',
          n: 1,
          source: 'DivisionManagementTab.deleteDivision.cascade.callback',
        );
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        showFailedSnackbar(context, '삭제 실패: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _deletingDivisionName = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(labelText: '새 회사 이름 (division)'),
            onSubmitted: (_) => _handleAddDivision(),
            enabled: !_adding && _deletingDivisionName == null,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: _adding
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_business),
            label: Text(_adding ? '추가 중...' : '회사 추가'),
            onPressed: _adding || _deletingDivisionName != null
                ? null
                : _handleAddDivision,
          ),
          const SizedBox(height: 20),
          const Text('등록된 회사 목록',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  itemCount: widget.divisionList.length,
                  itemBuilder: (context, index) {
                    final division = widget.divisionList[index];
                    final deleting = _deletingDivisionName == division;

                    return ListTile(
                      title: Text(division),
                      trailing: deleting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.redAccent),
                              onPressed:
                                  (_deletingDivisionName != null || _adding)
                                      ? null
                                      : () => _handleDeleteDivision(division),
                            ),
                    );
                  },
                ),
                if (_deletingDivisionName != null)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '삭제 중: $_deletingDivisionName',
                          style: const TextStyle(color: Colors.white),
                        ),
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
}
