import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'minor_departure_completed_plate_image_dialog.dart';

class MinorTodayLogSection extends StatefulWidget {
  const MinorTodayLogSection({
    super.key,
    required this.plateNumber,
    required this.logsRaw,
  });

  final String plateNumber;
  final List<dynamic> logsRaw;

  @override
  State<MinorTodayLogSection> createState() => _MinorTodayLogSectionState();
}

class _MinorTodayLogSectionState extends State<MinorTodayLogSection> {
  bool _expanded = false;

  // ===== 공통 로직: 로그 정규화 =====
  List<Map<String, dynamic>> _normalizeLogs(List<dynamic> raw) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ===== 공통 로직: 타임스탬프 파싱 =====
  DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;

    if (ts is Timestamp) return ts.toDate().toLocal();
    if (ts is DateTime) return ts.toLocal();

    if (ts is int) {
      if (ts > 100000000000) return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
      return DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
    }

    if (ts is String) {
      final parsed = DateTime.tryParse(ts);
      return parsed?.toLocal();
    }

    return null;
  }

  // ===== 공통 로직: 타임스탬프 포맷(로컬) =====
  String _formatTs(dynamic ts) {
    final dt = _parseTs(ts);
    if (dt == null) return '--';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  // ===== 원화 포맷 (intl 없이 콤마만) =====
  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  String _formatIntWithComma(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _formatWon(dynamic value) {
    final n = _asInt(value);
    if (n == null) return '-';
    return '₩${_formatIntWithComma(n)}';
  }

  // ===== 공통 로직: 액션에 따른 아이콘/색상 매핑 =====
  IconData _actionIcon(String action) {
    if (action.contains('사전 정산')) return Icons.receipt_long;
    if (action.contains('입차 완료')) return Icons.local_parking;
    if (action.contains('출차')) return Icons.exit_to_app;
    if (action.contains('취소')) return Icons.undo;
    if (action.contains('생성')) return Icons.add_circle_outline;
    return Icons.history;
  }

  Color _actionColor(BuildContext context, String action) {
    final cs = Theme.of(context).colorScheme;
    if (action.contains('사전 정산')) return cs.tertiary;
    if (action.contains('출차')) return cs.secondary;
    if (action.contains('취소')) return cs.error;
    if (action.contains('생성')) return cs.primary;
    return cs.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // 정규화 + "오래된순(오름차순)" 정렬
    final logs = _normalizeLogs(widget.logsRaw)
      ..sort((a, b) {
        final aT = _parseTs(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bT = _parseTs(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aT.compareTo(bT);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더: 번호판 영역(탭→펼치기/접기) + 사진 버튼
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${widget.plateNumber} 로그',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ) ??
                              TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: "사진 보기",
                    transitionDuration: const Duration(milliseconds: 300),
                    pageBuilder: (_, __, ___) =>
                        MinorDepartureCompletedPlateImageDialog(plateNumber: widget.plateNumber),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant.withOpacity(0.7)),
                  backgroundColor: cs.surfaceContainerLow,
                ),
                icon: const Icon(Icons.photo, size: 18),
                label: const Text('사진', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.65)),

        // 본문 리스트: 번호판 영역을 눌러야 펼쳐짐
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: !_expanded
                ? Center(
              key: const ValueKey('collapsed'),
              child: Text(
                '번호판 영역을 눌러 로그를 펼치세요.',
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
                : (logs.isEmpty
                ? Center(
              key: const ValueKey('empty'),
              child: Text(
                '📭 로그가 없습니다.',
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
                : Scrollbar(
              key: const ValueKey('list'),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: logs.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: cs.outlineVariant.withOpacity(0.55)),
                itemBuilder: (context, index) {
                  final e = logs[index];

                  final action = (e['action'] ?? '-').toString();
                  final from = (e['from'] ?? '').toString();
                  final to = (e['to'] ?? '').toString();
                  final performedBy = (e['performedBy'] ?? '').toString();
                  final tsText = _formatTs(e['timestamp']);

                  final String? feeText = (e.containsKey('lockedFee') || e.containsKey('lockedFeeAmount'))
                      ? _formatWon(e['lockedFee'] ?? e['lockedFeeAmount'])
                      : null;
                  final String? payText =
                  (e['paymentMethod']?.toString().trim().isNotEmpty ?? false)
                      ? e['paymentMethod'].toString()
                      : null;
                  final String? reasonText =
                  (e['reason']?.toString().trim().isNotEmpty ?? false)
                      ? e['reason'].toString()
                      : null;

                  final color = _actionColor(context, action);

                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Icon(_actionIcon(action), color: color),
                    title: Text(
                      action,
                      style: TextStyle(fontWeight: FontWeight.w900, color: color),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (from.isNotEmpty || to.isNotEmpty)
                          Text(
                            '$from → $to',
                            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        if (performedBy.isNotEmpty) const SizedBox(height: 2),
                        if (performedBy.isNotEmpty)
                          Text('담당자:', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        if (performedBy.isNotEmpty)
                          Text(performedBy, style: text.bodySmall?.copyWith(color: cs.onSurface)),
                        if (feeText != null || payText != null || reasonText != null)
                          const SizedBox(height: 2),
                        if (feeText != null)
                          Text('확정요금: $feeText', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        if (payText != null)
                          Text('결제수단: $payText', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        if (reasonText != null)
                          Text('사유: $reasonText', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                    trailing: Text(tsText, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    isThreeLine: true,
                  );
                },
              ),
            )),
          ),
        ),
      ],
    );
  }
}
