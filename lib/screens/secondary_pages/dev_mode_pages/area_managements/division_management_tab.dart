import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
  String? _deletingDivisionName; // 동시에 하나만 삭제

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleAddDivision() async {
    if (_adding) return;

    final input = _controller.text.trim();
    if (input.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회사 이름을 입력해주세요.')),
      );
      return;
    }
    // 파이어스토어 문서 ID에서 '/'는 허용되지 않음
    if (input.contains('/')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회사 이름에 "/" 문자는 사용할 수 없습니다.')),
      );
      return;
    }

    setState(() => _adding = true);
    try {
      // 부모 콜백: divisions/{name} 생성
      await widget.onDivisionAdded(input);

      // 비즈니스 규칙 유지: 본사 area 자동 생성 (areas/{division-division})
      final areaId = '$input-$input';
      await FirebaseFirestore.instance.collection('areas').doc(areaId).set({
        'name': input,
        'division': input,
        'isHeadquarter': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _controller.clear());
      FocusScope.of(context).unfocus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ 회사 "$input" 이(가) 추가되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 회사 추가 실패: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _adding = false);
    }
  }

  Future<void> _handleDeleteDivision(String division) async {
    if (_deletingDivisionName != null) {
      // 이미 다른 삭제가 진행 중
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('다른 삭제 작업이 진행 중입니다. 잠시만 기다려주세요.')),
      );
      return;
    }

    // 확인 다이얼로그
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('회사 삭제'),
        content: Text('"$division" 회사와 소속 지역을 모두 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    ) ??
        false;

    if (!ok) return;

    setState(() => _deletingDivisionName = division);
    try {
      // 부모 콜백: divisions/{division} 삭제 및 소속 areas 일괄 삭제(부모에서 배치 처리)
      await widget.onDivisionDeleted(division);

      // ✅ 중복 삭제 제거: 부모에서 이미 areas 전체 삭제하므로 아래 코드는 제거
      // final areaId = '$division-$division';
      // await FirebaseFirestore.instance.collection('areas').doc(areaId).delete();

      if (!mounted) return;
      // 삭제 성공 Snackbar는 부모에서 띄우므로 여기서는 생략(중복 방지). 필요 시 보강 가능.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 삭제 실패: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _deletingDivisionName = null);
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
              height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.add_business),
            label: Text(_adding ? '추가 중...' : '회사 추가'),
            onPressed: _adding || _deletingDivisionName != null ? null : _handleAddDivision,
          ),
          const SizedBox(height: 20),
          const Text('등록된 회사 목록', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: (_deletingDivisionName != null || _adding)
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
