import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../states/plate/filter_plate.dart';
import '../../../../utils/snackbar_helper.dart';
import 'plate_image_dialog.dart';

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
          '본 작업은 이하에 해당될 경우에만 수행하세요,\n'
          '1. 차량 사고 등의 이슈가 발생하였을 때.\n\n'
          '2. 고객 컴플레인 등의 이슈가 발생하였을 때.\n\n\n'
          '계속 하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('동의'),
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
      showSuccessSnackbar(context, '병합 로그가 새로고침되었습니다.');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = context.watch<FilterPlate>().searchQuery;

    final filteredLogs = widget.mergedLogs.where((log) {
      final plate = (log['plateNumber'] ?? '').toString();
      return searchQuery.isEmpty || plate.endsWith(searchQuery);
    }).toList()
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a['mergedAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = DateTime.tryParse(b['mergedAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime); // 최신 순 정렬
      });

    final totalLockedFee = filteredLogs.map((log) {
      final logs = (log['logs'] as List?) ?? [];
      final latestBill = logs
          .whereType<Map<String, dynamic>>()
          .where((l) => l['action'] == '사전 정산')
          .fold<Map<String, dynamic>?>(null, (prev, curr) {
        final currTime = DateTime.tryParse(curr['timestamp'] ?? '');
        final prevTime = prev != null ? DateTime.tryParse(prev['timestamp'] ?? '') : null;
        if (prevTime == null || (currTime != null && currTime.isAfter(prevTime))) return curr;
        return prev;
      });
      return latestBill?['lockedFee'] as num? ?? 0;
    }).fold<num>(0, (sum, fee) => sum + fee);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
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
          final mergedAt = DateTime.tryParse(log['mergedAt'] ?? '')?.toLocal();
          final formattedTime = mergedAt != null
              ? "${mergedAt.hour.toString().padLeft(2, '0')}:${mergedAt.minute.toString().padLeft(2, '0')}:${mergedAt.second.toString().padLeft(2, '0')}"
              : '-';

          final isExpanded = _expandedPlates.contains(plate);

          final latestBillLog = (logs as List)
              .whereType<Map<String, dynamic>>()
              .where((l) => l['action'] == '사전 정산')
              .fold<Map<String, dynamic>?>(null, (prev, curr) {
            final currTime = DateTime.tryParse(curr['timestamp'] ?? '');
            final prevTime = prev != null ? DateTime.tryParse(prev['timestamp'] ?? '') : null;
            if (prevTime == null || (currTime != null && currTime.isAfter(prevTime))) {
              return curr;
            }
            return prev;
          });

          final billTypeText = latestBillLog?['billType']?.toString() ?? '-';
          final paymentMethod = latestBillLog?['paymentMethod']?.toString() ?? '-';
          final lockedFee = latestBillLog?['lockedFee'] ?? '-';

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
                      Expanded(
                          flex: 2, child: Center(child: Text(formattedTime, style: const TextStyle(fontSize: 18)))),
                      Expanded(flex: 5, child: Center(child: Text(plate, style: const TextStyle(fontSize: 18)))),
                      Expanded(
                          flex: 3,
                          child: Center(child: Text(billTypeText, style: const TextStyle(fontSize: 16)))),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                Container(
                  color: Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: Row(
                                    children: [
                                      const Icon(Icons.article_outlined, color: Colors.blueGrey),
                                      const SizedBox(width: 8),
                                      Text('$plate 로그', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  contentPadding: const EdgeInsets.all(16),
                                  content: Container(
                                    constraints: const BoxConstraints(maxHeight: 500, maxWidth: 600),
                                    decoration: BoxDecoration(
                                      color: Colors.white, // ✅ 밝은 배경으로 전환
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SingleChildScrollView(
                                        child: Text(
                                          const JsonEncoder.withIndent('  ').convert(logs),
                                          style: const TextStyle(
                                            fontSize: 12,                     // ✅ 폰트 크기 증가
                                            fontFamily: 'monospace',          // ✅ Android 대응 고정폭
                                            color: Colors.black,              // ✅ 흰배경 대비 검정 글자
                                            height: 1.5,                      // ✅ 줄 간격 증가
                                          ),
                                        ),
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
                            onPressed: () {
                              showGeneralDialog(
                                context: context,
                                barrierDismissible: true,
                                barrierLabel: "사진 보기",
                                transitionDuration: const Duration(milliseconds: 300),
                                pageBuilder: (_, __, ___) => PlateImageDialog(plateNumber: plate),
                              );
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade100),
                            child: const Text('사진'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '결제 금액: ₩$lockedFee ($paymentMethod)',
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
