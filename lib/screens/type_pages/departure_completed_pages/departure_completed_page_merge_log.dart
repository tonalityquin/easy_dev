import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../states/plate/filter_plate.dart';

class MergedLogSection extends StatefulWidget {
  final List<Map<String, dynamic>> mergedLogs;
  final String division;
  final String area;
  final DateTime selectedDate;

  const MergedLogSection({
    super.key,
    required this.mergedLogs,
    required this.division,
    required this.area,
    required this.selectedDate,
  });

  @override
  State<MergedLogSection> createState() => _MergedLogSectionState();
}

class _MergedLogSectionState extends State<MergedLogSection> {
  final Set<String> _expandedPlates = {};

  Future<void> _refreshMergedLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('병합 로그 새로고침'),
        content: const Text(
          '이 작업은 GCS에서 병합 로그를 새로 불러오며,\n'
              '약간의 데이터 사용량이 발생할 수 있습니다.\n\n'
              '계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('동의하고 새로고침'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    final d = widget.selectedDate;
    final cacheKey = 'mergedLogCache-${widget.division}-${widget.area}-${d.year}-${d.month}-${d.day}';

    await prefs.remove(cacheKey);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('병합 로그가 새로고침되었습니다.')),
      );
      setState(() {}); // UI 재로드 트리거
    }
  }

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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '🔒 병합 로그 항목',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _refreshMergedLogs,
              icon: const Icon(Icons.refresh),
              label: const Text('새로고침'),
            ),
          ],
        ),
        if (filteredLogs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('병합 로그가 없습니다.')),
          ),
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
        ...filteredLogs.map((log) {
          final plate = log['plateNumber'] ?? 'Unknown';
          final logs = log['logs'] ?? [];
          final type = log['type'] ?? '미지정';
          final mergedAt = DateTime.tryParse(log['mergedAt'] ?? '')?.toLocal();
          final formattedTime = mergedAt != null
              ? "${mergedAt.hour.toString().padLeft(2, '0')}:${mergedAt.minute.toString().padLeft(2, '0')}:${mergedAt.second.toString().padLeft(2, '0')}"
              : '-';

          final isExpanded = _expandedPlates.contains(plate);

          final totalFee = log['totalFee'] ?? (logs is List
              ? logs.map((e) => e['fee'] ?? e['lockedFeeAmount'])
              .whereType<num>()
              .fold(0.0, (sum, fee) => sum + fee)
              : 0.0);

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
                  child: Column(
                    children: [
                      Row(
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
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade400),
                            child: const Text('사진'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '총 정산 금액: ₩${totalFee.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
