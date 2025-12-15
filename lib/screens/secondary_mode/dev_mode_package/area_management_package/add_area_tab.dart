import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../utils/snackbar_helper.dart';
// ✅ UsageReporter 계측 추가
import '../../../../../utils/usage/usage_reporter.dart';

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

  bool _adding = false; // 추가 이중 클릭 방지
  String? _deletingAreaName; // 동시에 하나만 삭제

  Future<List<String>>? _areasFuture; // FutureBuilder 재호출 최소화

  // ✅ 신규: 지역 생성 시 적용할 모드 선택
  //  - service: 서비스 모드 전용
  //  - lite: Lite 모드 전용
  //  - both: 공용(서비스+Lite)
  String _selectedModeKey = 'service';

  static const List<_ModeItem> _modeItems = <_ModeItem>[
    _ModeItem(key: 'service', label: '서비스 모드'),
    _ModeItem(key: 'lite', label: 'Lite 모드'),
    _ModeItem(key: 'both', label: '공용(서비스+Lite)'),
  ];

  @override
  void initState() {
    super.initState();
    _areasFuture = _loadAreas(); // 초기 캐시
  }

  @override
  void didUpdateWidget(covariant AddAreaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 부모에서 selectedDivision이 바뀐 경우에만 갱신
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

  // 입력 정규화: 선후 공백 제거, '/' → '-', 다중 공백 1개로
  String _norm(String s) => s.trim().replaceAll('/', '-').replaceAll(RegExp(r'\s+'), ' ');

  List<String> _toModes(String key) {
    switch (key) {
      case 'lite':
        return const ['lite'];
      case 'both':
        return const ['service', 'lite'];
      case 'service':
      default:
        return const ['service'];
    }
  }

  Future<void> _addArea() async {
    if (_adding) return;

    final rawKr = _areaController.text;
    final areaName = _norm(rawKr);
    final englishAreaName = _englishAreaController.text.trim();
    final division = widget.selectedDivision;

    if (division == null || division.isEmpty) {
      showFailedSnackbar(context, '먼저 회사를 선택하세요.');
      return;
    }
    if (areaName.isEmpty) {
      showFailedSnackbar(context, '새 지역 이름(한글)을 입력하세요.');
      return;
    }

    final areaId = '$division-$areaName';
    final modes = _toModes(_selectedModeKey);

    setState(() => _adding = true);

    try {
      final fs = FirebaseFirestore.instance;
      final ref = fs.collection('areas').doc(areaId);

      int reads = 0;
      int writes = 0;

      // 중복 생성/경합 방지: 트랜잭션으로 존재 확인 후 생성
      await fs.runTransaction((tx) async {
        final snap = await tx.get(ref);
        reads += 1; // ✅ Firestore READ

        if (snap.exists) {
          throw Exception('이미 존재하는 지역입니다.');
        }
        tx.set(ref, {
          'name': areaName,
          'englishName': englishAreaName,
          'division': division,
          // ✅ 신규: 서비스/Lite 공용 여부 저장
          //    예) 서비스: ['service'], Lite: ['lite'], 공용: ['service','lite']
          'modes': modes,
          'createdAt': FieldValue.serverTimestamp(),
        });
        writes += 1; // ✅ Firestore WRITE
      });

      // ✅ 계측: 트랜잭션 내 read/write 각각 보고
      try {
        if (reads > 0) {
          await UsageReporter.instance.report(
            area: division,
            action: 'read',
            n: reads,
            source: 'AddAreaTab._addArea.areas.tx.get:$areaId',
          );
        }
        if (writes > 0) {
          await UsageReporter.instance.report(
            area: division,
            action: 'write',
            n: writes,
            source: 'AddAreaTab._addArea.areas.tx.set:$areaId',
          );
        }
      } catch (_) {}

      if (!mounted) return;

      _areaController.clear();
      _englishAreaController.clear();
      FocusScope.of(context).unfocus();

      setState(() {
        _areasFuture = _loadAreas(); // 목록 재로딩 (Future 캐시 갱신)
      });

      showSuccessSnackbar(context, '✅ "$areaName" 지역이 추가되었습니다');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '❌ 지역 추가 실패: $e');
    } finally {
      // ⛔️ return 금지: mounted만 체크하고 상태만 정리
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  Future<List<String>> _loadAreas() async {
    final division = widget.selectedDivision;
    if (division == null || division.isEmpty) return [];
    final snapshot = await FirebaseFirestore.instance
        .collection('areas')
        .where('division', isEqualTo: division)
        .get(const GetOptions(source: Source.serverAndCache));

    // ✅ 계측: areas read (결과 0이어도 최소 1로 보고)
    final readN = snapshot.docs.isEmpty ? 1 : snapshot.docs.length;
    try {
      await UsageReporter.instance.report(
        area: division,
        action: 'read',
        n: readN,
        source: 'AddAreaTab._loadAreas.areas.query',
      );
    } catch (_) {}

    final list = snapshot.docs
        .map((e) => (e['name'] as String?)?.trim())
        .whereType<String>()
        .toList()
      ..sort((a, b) => a.compareTo(b)); // 정렬 일관성
    return list;
  }

  Future<void> _deleteArea(String areaName) async {
    if (_deletingAreaName != null) {
      showFailedSnackbar(context, '다른 삭제 작업이 진행 중입니다. 잠시만 기다려주세요.');
      return;
    }

    final division = widget.selectedDivision;
    if (division == null || division.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지역 삭제'),
        content: Text('"$areaName" 지역을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );

    if (confirm != true) return;

    // 🔒 async gap(showDialog) 이후 컨텍스트 사용 전 확인
    if (!mounted) return;

    setState(() => _deletingAreaName = areaName);

    try {
      final areaId = '$division-$areaName';
      await FirebaseFirestore.instance.collection('areas').doc(areaId).delete();

      // ✅ 계측: areas delete 1
      try {
        await UsageReporter.instance.report(
          area: division,
          action: 'delete',
          n: 1,
          source: 'AddAreaTab._deleteArea.areas.delete:$areaId',
        );
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _areasFuture = _loadAreas(); // 목록 재로딩 (Future 캐시 갱신)
      });

      showSuccessSnackbar(context, '🗑️ "$areaName" 지역이 삭제되었습니다');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '❌ 삭제 실패: $e');
    } finally {
      // ⛔️ return 금지: mounted만 확인하고 상태만 정리
      if (mounted) {
        setState(() => _deletingAreaName = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _adding || _deletingAreaName != null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: widget.selectedDivision,
            items: widget.divisionList
                .map((div) => DropdownMenuItem(value: div, child: Text(div)))
                .toList(),
            onChanged: busy
                ? null
                : (val) {
              // 부모 콜백 호출 + 로컬 Future 캐시 갱신
              widget.onDivisionChanged(val);
              setState(() {
                _areasFuture = _loadAreas();
              });
            },
            decoration: const InputDecoration(labelText: '회사 선택'),
          ),
          const SizedBox(height: 12),

          // ✅ 신규: 모드 선택
          DropdownButtonFormField<String>(
            value: _selectedModeKey,
            items: _modeItems
                .map((m) => DropdownMenuItem<String>(
              value: m.key,
              child: Text(m.label),
            ))
                .toList(),
            onChanged: busy ? null : (v) => setState(() => _selectedModeKey = v ?? 'service'),
            decoration: const InputDecoration(labelText: '추가할 지역의 모드'),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _areaController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: '새 지역 이름(한글)'),
            onSubmitted: (_) => _addArea(),
            enabled: !busy,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _englishAreaController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: '새 지역 이름 (영어)'),
            onSubmitted: (_) => _addArea(),
            enabled: !busy,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: _adding
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add),
            label: Text(_adding ? '추가 중...' : '지역 추가'),
            onPressed: busy ? null : _addArea,
          ),
          const SizedBox(height: 20),
          const Text('해당 회사의 지역 목록', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: widget.selectedDivision == null
                ? const Center(child: Text('📌 회사를 먼저 선택하세요.'))
                : FutureBuilder<List<String>>(
              future: _areasFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final areas = snapshot.data ?? const <String>[];
                if (areas.isEmpty) {
                  return const Center(child: Text('등록된 지역이 없습니다.'));
                }

                return ListView.builder(
                  itemCount: areas.length,
                  itemBuilder: (context, index) {
                    final areaName = areas[index];
                    final deleting = _deletingAreaName == areaName;
                    return ListTile(
                      key: ValueKey(areaName), // 리빌드 안정성
                      title: Text(areaName),
                      trailing: deleting
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : IconButton(
                        tooltip: '지역 삭제',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: busy ? null : () => _deleteArea(areaName),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeItem {
  final String key;
  final String label;
  const _ModeItem({required this.key, required this.label});
}
