import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../../utils/usage/usage_reporter.dart';

String _formatAnyDate(dynamic v) {
  if (v == null) return '시간 정보 없음';
  if (v is Timestamp) return DateFormat('yyyy-MM-dd HH:mm:ss').format(v.toDate());
  if (v is String) {
    final dt = DateTime.tryParse(v);
    if (dt != null) return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
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
        const SizedBox(width: 130, child: SizedBox.shrink()),
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 18))),
      ],
    ),
  );
}

/// ✅ (정책 반영) plate_status 샤딩 경로
const String _plateStatusRoot = 'plate_status';
const String _monthsSub = 'months';
const String _platesSub = 'plates';

const String _monthlyPlateStatusRoot = 'monthly_plate_status';

String _safeArea(String area) {
  final a = area.trim();
  return a.isEmpty ? 'unknown' : a;
}

String _monthKey(DateTime dt) => '${dt.year}${dt.month.toString().padLeft(2, '0')}';

String _canonicalPlateNumber(String plateNumber) {
  final t = plateNumber.trim().replaceAll(' ', '');
  final raw = t.replaceAll('-', '');
  final m = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$').firstMatch(raw);
  if (m == null) return t;
  return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
}

/// ✅ 단일 docId 규칙: "{plate(하이픈 포함)}_{area}"
String _plateDocId(String plateNumber, String area) {
  final a = _safeArea(area);
  final p = _canonicalPlateNumber(plateNumber);
  return '${p}_$a';
}

Future<Map<String, dynamic>?> _fetchPlateStatusSharded({
  required FirebaseFirestore firestore,
  required String plateNumber,
  required String area,
}) async {
  final safeArea = _safeArea(area);
  final docId = _plateDocId(plateNumber, safeArea);

  final now = DateTime.now();
  final monthsToTry = <DateTime>[
    DateTime(now.year, now.month, 1),
    DateTime(now.year, now.month - 1, 1),
  ];

  try {
    // 1) 빠른 경로: 현재월/전월
    for (final m in monthsToTry) {
      final mk = _monthKey(m);

      final doc = await firestore
          .collection(_plateStatusRoot)
          .doc(safeArea)
          .collection(_monthsSub)
          .doc(mk)
          .collection(_platesSub)
          .doc(docId)
          .get();

      if (doc.exists) return doc.data();
    }

    // 2) 폴백: collectionGroup('plates')에서 docId로 검색(인덱스/규칙 미지원이면 실패 가능)
    try {
      final qs = await firestore
          .collectionGroup(_platesSub)
          .where(FieldPath.documentId, isEqualTo: docId)
          .get();

      if (qs.docs.isNotEmpty) {
        QueryDocumentSnapshot<Map<String, dynamic>>? best;
        int bestMonth = -1;

        for (final d in qs.docs) {
          final path = d.reference.path;
          if (!path.contains('$_plateStatusRoot/$safeArea/$_monthsSub/')) continue;

          final parts = path.split('/');
          final monthsIndex = parts.indexOf(_monthsSub);
          if (monthsIndex < 0 || monthsIndex + 1 >= parts.length) continue;

          final mk = parts[monthsIndex + 1];
          final mkInt = int.tryParse(mk) ?? -1;

          if (mkInt > bestMonth) {
            bestMonth = mkInt;
            best = d;
          }
        }

        if (best != null) return best.data();
        return qs.docs.first.data();
      }
    } on FirebaseException catch (_) {
      // 규칙/인덱스 제한 시 조용히 무시(상위에서 null 처리)
    }

    return null;
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> _fetchMonthlyPlateStatus({
  required FirebaseFirestore firestore,
  required String plateNumber,
  required String area,
}) async {
  final safeArea = _safeArea(area);
  final docId = _plateDocId(plateNumber, safeArea);

  try {
    final doc = await firestore.collection(_monthlyPlateStatusRoot).doc(docId).get();
    if (doc.exists) return doc.data();
    return null;
  } catch (_) {
    return null;
  }
}

/// ✅ 정산 유형에 따라 조회 컬렉션을 분기하는 BottomSheet
/// - selectedBillType == '정기'  → monthly_plate_status (단일 doc)
/// - 그 외                     → plate_status (샤딩 경로)
///
/// 주의: 이 함수는 "조회/표시"만 합니다(쓰기 없음).
Future<Map<String, dynamic>?> tripleInputCustomStatusBottomSheet(
    BuildContext context,
    String plateNumber,
    String area, {
      required String selectedBillType,
    }) async {
  final firestore = FirebaseFirestore.instance;
  final safeArea = _safeArea(area);

  final bool isMonthly = selectedBillType.trim() == '정기';
  final String sourceLabel = isMonthly ? 'monthly_plate_status' : 'plate_status(sharded)';

  Map<String, dynamic>? data;
  try {
    if (isMonthly) {
      data = await _fetchMonthlyPlateStatus(
        firestore: firestore,
        plateNumber: plateNumber,
        area: safeArea,
      );
    } else {
      data = await _fetchPlateStatusSharded(
        firestore: firestore,
        plateNumber: plateNumber,
        area: safeArea,
      );
    }
  } finally {
    // ✅ 계측은 항상 1회로 보고(정책 유지)
    await UsageReporter.instance.report(
      area: safeArea,
      action: 'read',
      n: 1,
      source: 'tripleInputCustomStatusBottomSheet/$sourceLabel.read',
      useSourceOnlyKey: true,
    );
  }

  if (data == null || data.isEmpty) return null;

  final String? customStatus = (data['customStatus'] as String?)?.trim();
  final Timestamp? updatedAt = data['updatedAt'];
  final List<String> statusList =
      (data['statusList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

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
              border: Border.all(color: cs.outlineVariant.withOpacity(0.70)),
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
                      color: cs.outlineVariant.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),

                Row(
                  children: [
                    Icon(
                      (customStatus != null && customStatus.isNotEmpty)
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      color: (customStatus != null && customStatus.isNotEmpty)
                          ? cs.error
                          : cs.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      (customStatus != null && customStatus.isNotEmpty) ? '주의사항' : '상세 정보',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Text(
                  '데이터 출처: $sourceLabel',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),

                const SizedBox(height: 20),

                if (customStatus != null && customStatus.isNotEmpty) ...[
                  Text(
                    customStatus,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                Row(
                  children: [
                    Icon(Icons.access_time, size: 20, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      '최종 수정: $formattedUpdatedAt',
                      style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),

                if (statusList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    '저장된 상태',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
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
                            color: cs.onSurface,
                          ),
                        ),
                        backgroundColor: cs.surfaceContainerLow,
                        side: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                    )
                        .toList(),
                  ),
                ],

                const SizedBox(height: 24),
                Text(
                  '상세 정보',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
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

                if (paymentHistory.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    '결제 내역',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
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
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
                        borderRadius: BorderRadius.circular(10),
                        color: cs.surface,
                      ),
                      child: ListTile(
                        title: Text(
                          '금액: ${amount ?? '-'}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
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
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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
    'source': sourceLabel,
  };
}
