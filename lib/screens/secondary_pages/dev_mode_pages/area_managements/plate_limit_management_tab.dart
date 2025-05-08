import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // ✅ PlateState 접근을 위해 필요
import '../../../../states/plate/plate_state.dart'; // ✅ PlateState import 경로 맞게 조정

class PlateLimitManagementTab extends StatefulWidget {
  const PlateLimitManagementTab({super.key});

  @override
  State<PlateLimitManagementTab> createState() => _PlateLimitManagementTabState();
}

class _PlateLimitManagementTabState extends State<PlateLimitManagementTab> {
  /// plate type 종류 정의
  final plateTypes = ['parkingRequests', 'parkingCompleted', 'departureRequests', 'departureCompleted'];

  /// 각 지역의 plate type별 limit 값
  final Map<String, Map<String, TextEditingController>> _controllers = {};

  @override
  void initState() {
    super.initState();
    _loadLimits();
  }

  /// Firestore에서 area_limits 불러오기
  Future<void> _loadLimits() async {
    final snapshot = await FirebaseFirestore.instance.collection('area_limits').get();

    final newControllers = <String, Map<String, TextEditingController>>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final areaId = doc.id;

      newControllers[areaId] = {
        for (final type in plateTypes)
          type: TextEditingController(text: (data[type] ?? 6).toString()),
      };
    }

    // 기존 controller 정리 및 교체
    _controllers.forEach((_, typeMap) {
      for (final controller in typeMap.values) {
        controller.dispose();
      }
    });

    setState(() {
      _controllers
        ..clear()
        ..addAll(newControllers);
    });
  }

  /// Firestore에 limit 값 저장 + PlateState 동기화
  Future<void> _updateLimit(String rawArea, String type, int value) async {
    try {
      // ✅ 하이픈 뒤쪽만 문서 ID로 사용
      final area = rawArea.contains('-') ? rawArea.split('-').last : rawArea;

      await FirebaseFirestore.instance
          .collection('area_limits')
          .doc(area)
          .set({type: value}, SetOptions(merge: true));

      // ✅ PlateState 재구독
      if (context.mounted) {
        final plateState = context.read<PlateState>();
        plateState.syncWithAreaState();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ [$area] $type 리밋이 $value로 저장되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 저장 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controllers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: _controllers.entries.map((entry) {
        final area = entry.key;
        final areaControllers = entry.value;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📍 Area: $area', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...plateTypes.map((type) {
                  final controller = areaControllers[type]!;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(type)),
                        SizedBox(
                          width: 60,
                          child: TextField(
                            controller: controller,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.save),
                          tooltip: '저장',
                          onPressed: () {
                            final newLimit = int.tryParse(controller.text);
                            if (newLimit != null && newLimit >= 0) {
                              _updateLimit(area, type, newLimit);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('❗ 유효한 숫자를 입력해주세요')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    for (final map in _controllers.values) {
      for (final controller in map.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }
}
