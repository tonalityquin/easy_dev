import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../../utils/usage/usage_reporter.dart';

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

Widget _infoRow(BuildContext context, String label, String? value) {
  if (value == null || value.isEmpty) return const SizedBox.shrink();

  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;

  final labelStyle = (tt.titleMedium ?? const TextStyle(fontSize: 18))
      .copyWith(fontWeight: FontWeight.w800, color: cs.onSurface);
  final valueStyle =
  (tt.titleMedium ?? const TextStyle(fontSize: 18)).copyWith(color: cs.onSurface);

  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: labelStyle),
        ),
        Expanded(
          child: Text(value, style: valueStyle),
        ),
      ],
    ),
  );
}

/// ✅ 정산 유형에 따라 조회 컬렉션을 분기하는 BottomSheet
/// - selectedBillType == '정기'  → monthly_plate_status
/// - 그 외                     → plate_status
///
/// 주의: 이 함수는 "조회/표시"만 합니다(쓰기 없음).
Future<Map<String, dynamic>?> minorInputCustomStatusBottomSheet(
    BuildContext context,
    String plateNumber,
    String area, {
      required String selectedBillType,
    }) async {
  final docId = '${plateNumber}_$area';

  final bool isMonthly = selectedBillType.trim() == '정기';
  final String collectionName = isMonthly ? 'monthly_plate_status' : 'plate_status';

  DocumentSnapshot<Map<String, dynamic>>? docSnapshot;
  try {
    docSnapshot = await FirebaseFirestore.instance.collection(collectionName).doc(docId).get();
  } on FirebaseException catch (e) {
    debugPrint('[minorInputCustomStatusBottomSheet] FirebaseException: ${e.code} ${e.message}');
    docSnapshot = null;
  } catch (e) {
    debugPrint('[minorInputCustomStatusBottomSheet] error: $e');
    docSnapshot = null;
  } finally {
    await UsageReporter.instance.report(
      area: (area.isEmpty ? 'unknown' : area),
      action: 'read',
      n: 1,
      source: 'minorInputCustomStatusBottomSheet/$collectionName.doc.get',
      useSourceOnlyKey: true,
    );
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
  final int? regularDurationHours =
  data['regularDurationHours'] is int ? data['regularDurationHours'] as int : null;

  final List<Map<String, dynamic>> paymentHistory =
      (data['payment_history'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ??
          [];

  final formattedUpdatedAt = _formatAnyDate(updatedAt);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final tt = Theme.of(context).textTheme;

      final bool hasWarning = customStatus != null && customStatus.isNotEmpty;
      final Color headerIconColor = hasWarning ? cs.error : cs.primary;
      final IconData headerIcon = hasWarning ? Icons.warning_amber_rounded : Icons.info_outline;
      final String headerTitle = hasWarning ? '주의사항' : '상세 정보';

      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                top: BorderSide(color: cs.outlineVariant.withOpacity(0.8)),
              ),
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
                      color: cs.outlineVariant.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),

                // 상단 타이틀
                Row(
                  children: [
                    Icon(headerIcon, color: headerIconColor, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      headerTitle,
                      style: (tt.headlineSmall ?? const TextStyle(fontSize: 24))
                          .copyWith(fontWeight: FontWeight.w900, color: cs.onSurface),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ✅ 어떤 컬렉션을 보고 있는지 표기(디버깅/오해 방지)
                Text(
                  '데이터 출처: $collectionName',
                  style: (tt.bodySmall ?? const TextStyle(fontSize: 14))
                      .copyWith(color: cs.onSurfaceVariant),
                ),

                const SizedBox(height: 20),

                // 메인 상태 텍스트
                if (hasWarning) ...[
                  Text(
                    customStatus,
                    style: (tt.titleMedium ?? const TextStyle(fontSize: 20)).copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 업데이트 시간
                Row(
                  children: [
                    Icon(Icons.access_time, size: 20, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      '최종 수정: $formattedUpdatedAt',
                      style: (tt.bodyMedium ?? const TextStyle(fontSize: 16))
                          .copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),

                // 저장된 상태 리스트
                if (statusList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    '저장된 상태',
                    style: (tt.titleMedium ?? const TextStyle(fontSize: 18))
                        .copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        backgroundColor: cs.primaryContainer,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        side: BorderSide(color: cs.outlineVariant.withOpacity(0.65)),
                      ),
                    )
                        .toList(),
                  ),
                ],

                // 정기/부가 메타 정보
                const SizedBox(height: 24),
                Text(
                  '상세 정보',
                  style: (tt.titleMedium ?? const TextStyle(fontSize: 18))
                      .copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
                ),
                const SizedBox(height: 12),
                _infoRow(context, 'Type', type),
                _infoRow(context, 'Count Type', countType),
                _infoRow(context, 'Regular Type', regularType),
                _infoRow(context, 'Regular Amount', regularAmount?.toString()),
                _infoRow(context, 'Regular Duration (hours)', regularDurationHours?.toString()),
                _infoRow(context, 'Period Unit', periodUnit),
                _infoRow(context, 'Start Date', startDate),
                _infoRow(context, 'End Date', endDate),

                // 결제 내역
                if (paymentHistory.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    '결제 내역',
                    style: (tt.titleMedium ?? const TextStyle(fontSize: 18))
                        .copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
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
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.9)),
                        borderRadius: BorderRadius.circular(10),
                        color: cs.surface,
                      ),
                      child: ListTile(
                        title: Text(
                          '금액: ${amount ?? '-'}',
                          style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (paidAt.isNotEmpty)
                              Text('결제시간: $paidAt', style: TextStyle(color: cs.onSurfaceVariant)),
                            if (paidBy != null && paidBy.isNotEmpty)
                              Text('결제자: $paidBy', style: TextStyle(color: cs.onSurfaceVariant)),
                            if (extended != null)
                              Text('연장결제: $extended', style: TextStyle(color: cs.onSurfaceVariant)),
                            if (note != null && note.toString().isNotEmpty)
                              Text('비고: $note', style: TextStyle(color: cs.onSurfaceVariant)),
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
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
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
    'collection': collectionName,
  };
}
