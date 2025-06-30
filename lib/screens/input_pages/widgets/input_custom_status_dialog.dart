import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// 기존에는 String?만 반환했지만,
/// 이제 Map<String, dynamic>? 형태로 반환하여
/// customStatus와 statusList를 함께 반환합니다.
Future<Map<String, dynamic>?> showInputCustomStatusDialog(
    BuildContext context,
    String plateNumber,
    String area,
    ) async {
  final docId = '${plateNumber}_$area';
  final docSnapshot = await FirebaseFirestore.instance
      .collection('plate_status')
      .doc(docId)
      .get();

  if (docSnapshot.exists) {
    final data = docSnapshot.data();
    final customStatus = data?['customStatus'];
    final Timestamp? updatedAt = data?['updatedAt'];
    final List<dynamic>? statusListRaw = data?['statusList'];

    final statusList = statusListRaw
        ?.map((e) => e.toString())
        .toList();

    // 상태 메모가 있으면 다이얼로그 표시
    if (customStatus != null && customStatus.toString().trim().isNotEmpty) {
      final formattedTime = updatedAt != null
          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(updatedAt.toDate())
          : '시간 정보 없음';

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('주의사항'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customStatus,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    '최종 수정: $formattedTime',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              if (statusList != null && statusList.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  '저장된 상태:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: statusList.map((status) {
                    return Chip(
                      label: Text(status),
                      backgroundColor: Colors.orange.withOpacity(0.1),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('확인'),
            ),
          ],
        ),
      );

      return {
        'customStatus': customStatus,
        'statusList': statusList ?? [],
      };
    }
  }

  return null; // 문서가 없거나 customStatus가 없으면 null
}
