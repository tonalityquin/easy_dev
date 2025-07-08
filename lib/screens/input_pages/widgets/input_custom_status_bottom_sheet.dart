import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

Future<Map<String, dynamic>?> inputCustomStatusBottomSheet(
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
    final statusList = statusListRaw?.map((e) => e.toString()).toList();

    if (customStatus != null && customStatus.toString().trim().isNotEmpty) {
      final formattedTime = updatedAt != null
          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(updatedAt.toDate())
          : '시간 정보 없음';

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),

                    // Title
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 30),
                        SizedBox(width: 10),
                        Text(
                          '주의사항',
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Main Status Text
                    Text(
                      customStatus,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                      maxLines: null,
                    ),

                    const SizedBox(height: 24),

                    // Updated time
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 22, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          '최종 수정: $formattedTime',
                          style: const TextStyle(fontSize: 21, color: Colors.grey),
                        ),
                      ],
                    ),

                    // Saved status list
                    if (statusList != null && statusList.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      const Text(
                        '저장된 상태',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: statusList.map((status) {
                          return Chip(
                            avatar: const Icon(Icons.label_important, size: 20, color: Colors.redAccent),
                            label: Text(
                              status,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: Colors.orange.withOpacity(0.15),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 40),

                    // Confirm button
                    Center(
                      child: SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            textStyle: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('확인'),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

      return {
        'customStatus': customStatus,
        'statusList': statusList ?? [],
      };
    }
  }

  return null;
}
