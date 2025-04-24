import 'dart:convert';
import 'package:flutter/material.dart';

class MergedLogSection extends StatelessWidget {
  final List<Map<String, dynamic>> mergedLogs;

  const MergedLogSection({super.key, required this.mergedLogs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Text(
          '🔒 병합 로그 항목',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (mergedLogs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('병합 로그가 없습니다.')),
          ),

        // 헤더 행
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade200,
          child: Row(
            children: const [
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    '병합 시각',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Center(
                  child: Text(
                    '번호판',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Center(
                  child: Text(
                    '로그 보기',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 로그 항목들
        ...mergedLogs.map((log) {
          final plate = log['plateNumber'] ?? 'Unknown';
          final logs = log['logs'] ?? [];
          final mergedAt = DateTime.tryParse(log['mergedAt'] ?? '')?.toLocal();

          final formattedTime = mergedAt != null
              ? "${mergedAt.hour.toString().padLeft(2, '0')}:${mergedAt.minute.toString().padLeft(2, '0')}:${mergedAt.second.toString().padLeft(2, '0')}"
              : '-';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      formattedTime,
                      style: const TextStyle(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Center(
                    child: Text(
                      plate,
                      style: const TextStyle(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: ElevatedButton(
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
                            child: const Text('로그 보기'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
