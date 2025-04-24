import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/plate/filter_plate.dart';

class MergedLogSection extends StatefulWidget {
  final List<Map<String, dynamic>> mergedLogs;

  const MergedLogSection({super.key, required this.mergedLogs});

  @override
  State<MergedLogSection> createState() => _MergedLogSectionState();
}

class _MergedLogSectionState extends State<MergedLogSection> {
  final Set<String> _expandedPlates = {};

  @override
  Widget build(BuildContext context) {
    final searchQuery = context.watch<FilterPlate>().searchQuery;

    final filteredLogs = widget.mergedLogs.where((log) {
      final plate = (log['plateNumber'] ?? '').toString();
      return searchQuery.isEmpty || plate.endsWith(searchQuery);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Text(
          '🔒 병합 로그 항목',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (filteredLogs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('병합 로그가 없습니다.')),
          ),
        // 헤더
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade200,
          child: Row(
            children: const [
              Expanded(
                flex: 2,
                child: Center(child: Text('병합 시각', style: TextStyle(fontWeight: FontWeight.bold))),
              ),
              Expanded(
                flex: 5,
                child: Center(child: Text('번호판', style: TextStyle(fontWeight: FontWeight.bold))),
              ),
              Expanded(
                flex: 3,
                child: Center(child: Text('정산 유형', style: TextStyle(fontWeight: FontWeight.bold))),
              ),
            ],
          ),
        ),

        // 항목들
        ...filteredLogs.map((log) {
          final plate = log['plateNumber'] ?? 'Unknown';
          final logs = log['logs'] ?? [];
          final type = log['type'] ?? '미지정';
          final mergedAt = DateTime.tryParse(log['mergedAt'] ?? '')?.toLocal();
          final formattedTime = mergedAt != null
              ? "${mergedAt.hour.toString().padLeft(2, '0')}:${mergedAt.minute.toString().padLeft(2, '0')}:${mergedAt.second.toString().padLeft(2, '0')}"
              : '-';

          final isExpanded = _expandedPlates.contains(plate);

          return Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedPlates.remove(plate);
                    } else {
                      _expandedPlates.add(plate);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey)),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Center(child: Text(formattedTime, style: const TextStyle(fontSize: 18)))),
                      Expanded(flex: 5, child: Center(child: Text(plate, style: const TextStyle(fontSize: 18)))),
                      Expanded(flex: 3, child: Center(child: Text(type.toString(), style: const TextStyle(fontSize: 16)))),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                Container(
                  color: Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text('$plate 로그'),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: SingleChildScrollView(
                                  child: Text(
                                    const JsonEncoder.withIndent('  ').convert(logs),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('닫기'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('로그'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {}, // 기능 없음
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade400),
                        child: const Text('사진'),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}