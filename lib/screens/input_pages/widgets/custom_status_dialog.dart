import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

Future<void> showCustomStatusDialog(BuildContext context, String plateNumber, String area) async {
  final docId = '${plateNumber}_$area';
  final docSnapshot = await FirebaseFirestore.instance.collection('plate_status').doc(docId).get();

  if (docSnapshot.exists) {
    final data = docSnapshot.data();
    final customStatus = data?['customStatus'];
    final Timestamp? updatedAt = data?['updatedAt'];

    if (customStatus != null && customStatus.toString().trim().isNotEmpty) {
      final formattedTime =
          updatedAt != null ? DateFormat('yyyy-MM-dd HH:mm:ss').format(updatedAt.toDate()) : '시간 정보 없음';

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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange,
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }
}
