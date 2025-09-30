import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// import 'package:easydev/utils/usage_reporter.dart';

String _formatAnyDate(dynamic v) {
  if (v == null) return '시간 정보 없음';
  if (v is Timestamp) return DateFormat('yyyy-MM-dd HH:mm:ss').format(v.toDate());
  if (v is String) {
    try {
      final dt = DateTime.tryParse(v);
      if (dt != null) return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
    } catch (_) {}
    return v;
  }
  return v.toString();
}

Widget _infoRow(String label, String? value) {
  if (value == null || value.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ],
    ),
  );
}

Future<Map<String, dynamic>?> inputCustomStatusBottomSheet(
  BuildContext context,
  String plateNumber,
  String area,
) async {
  final docId = '${plateNumber}_$area';

  DocumentSnapshot<Map<String, dynamic>>? docSnapshot;
  try {
    docSnapshot = await FirebaseFirestore.instance.collection('plate_status').doc(docId).get();
  } on FirebaseException catch (e) {
    debugPrint('[inputCustomStatusBottomSheet] FirebaseException: ${e.code} ${e.message}');
    docSnapshot = null;
  } catch (e) {
    debugPrint('[inputCustomStatusBottomSheet] error: $e');
    docSnapshot = null;
  } finally {
    /*await UsageReporter.instance.report(
      area: (area.isEmpty ? 'unknown' : area),
      action: 'read',
      n: 1,
      source: 'inputCustomStatusBottomSheet/plate_status.doc.get',
    );*/
  }

  if (docSnapshot == null || !docSnapshot.exists) return null;

  final data = docSnapshot.data() ?? {};

  final String? customStatus = (data['customStatus'] as String?)?.trim();
  final Timestamp? updatedAt = data['updatedAt'];
  final List<dynamic>? statusListRaw = data['statusList'];
  final List<String> statusList = statusListRaw?.map((e) => e.toString()).toList() ?? [];

  final String? countType = (data['countType'] as String?)?.trim();
  final String? type = (data['type'] as String?)?.trim();
  final String? periodUnit = (data['periodUnit'] as String?)?.trim();
  final String? regularType = (data['regularType'] as String?)?.trim();
  final String? startDate = (data['startDate'] as String?)?.trim();
  final String? endDate = (data['endDate'] as String?)?.trim();

  final int? regularAmount = data['regularAmount'] is int ? data['regularAmount'] as int : null;
  final int? regularDurationHours = data['regularDurationHours'] is int ? data['regularDurationHours'] as int : null;

  final List<Map<String, dynamic>> paymentHistory =
      (data['payment_history'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];

  final formattedUpdatedAt = _formatAnyDate(updatedAt);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
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

                // 상단 타이틀
                Row(
                  children: [
                    Icon(
                      (customStatus != null && customStatus.isNotEmpty)
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      color: (customStatus != null && customStatus.isNotEmpty) ? Colors.redAccent : Colors.blueAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      (customStatus != null && customStatus.isNotEmpty) ? '주의사항' : '상세 정보',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // 메인 상태 텍스트
                if (customStatus != null && customStatus.isNotEmpty) ...[
                  Text(
                    customStatus,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 업데이트 시간
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 20, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      '최종 수정: $formattedUpdatedAt',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),

                // 저장된 상태 리스트
                if (statusList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    '저장된 상태',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: statusList
                        .map(
                          (s) => Chip(
                            label: Text(
                              s,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            backgroundColor: Colors.orange.withOpacity(0.15),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          ),
                        )
                        .toList(),
                  ),
                ],

                // 정기/부가 메타 정보
                const SizedBox(height: 24),
                const Text(
                  '상세 정보',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _infoRow('Type', type),
                _infoRow('Count Type', countType),
                _infoRow('Regular Type', regularType),
                _infoRow('Regular Amount', regularAmount?.toString()),
                _infoRow('Regular Duration (hours)', regularDurationHours?.toString()),
                _infoRow('Period Unit', periodUnit),
                _infoRow('Start Date', startDate),
                _infoRow('End Date', endDate),

                // 결제 내역
                if (paymentHistory.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    '결제 내역',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ...paymentHistory.map((p) {
                    final amount = p['amount'];
                    final extended = p['extended'];
                    final note = p['note'];
                    final paidAt = _formatAnyDate(p['paidAt']);
                    final paidBy = p['paidBy']?.toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        title: Text(
                          '금액: ${amount ?? '-'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (paidAt.isNotEmpty) Text('결제시간: $paidAt'),
                            if (paidBy != null && paidBy.isNotEmpty) Text('결제자: $paidBy'),
                            if (extended != null) Text('연장결제: $extended'),
                            if (note != null && note.toString().isNotEmpty) Text('비고: $note'),
                          ],
                        ),
                        dense: true,
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('확인'),
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
    'customStatus': customStatus ?? '',
    'statusList': statusList,
    'type': type,
    'countType': countType,
    'regularType': regularType,
    'regularAmount': regularAmount,
    'regularDurationHours': regularDurationHours,
    'periodUnit': periodUnit,
    'startDate': startDate,
    'endDate': endDate,
    'payment_history': paymentHistory,
  };
}
