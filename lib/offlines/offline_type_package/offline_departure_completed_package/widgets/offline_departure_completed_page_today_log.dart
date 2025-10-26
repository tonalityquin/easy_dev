import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'offline_departure_completed_plate_image_dialog.dart';

class OfflineDepartureCompletedPageTodayLog extends StatefulWidget {
  const OfflineDepartureCompletedPageTodayLog({
    super.key,
    required this.plateNumber,
    required this.logsRaw,
  });

  final String plateNumber;
  final List<dynamic> logsRaw;

  @override
  State<OfflineDepartureCompletedPageTodayLog> createState() => _OfflineDepartureCompletedPageTodayLogState();
}

class _OfflineDepartureCompletedPageTodayLogState extends State<OfflineDepartureCompletedPageTodayLog> {
  bool _expanded = false;

  List<Map<String, dynamic>> _normalizeLogs(List<dynamic> raw) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

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

  String _formatTs(dynamic ts) {
    final dt = _parseTs(ts);
    if (dt == null) return '--';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

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

  IconData _actionIcon(String action) {
    if (action.contains('사전 정산')) return Icons.receipt_long;
    if (action.contains('입차 완료')) return Icons.local_parking;
    if (action.contains('출차')) return Icons.exit_to_app;
    if (action.contains('취소')) return Icons.undo;
    if (action.contains('생성')) return Icons.add_circle_outline;
    return Icons.history;
  }

  Color _actionColor(String action) {
    if (action.contains('사전 정산')) return Colors.teal;
    if (action.contains('출차')) return Colors.orange;
    if (action.contains('취소')) return Colors.redAccent;
    if (action.contains('생성')) return Colors.indigo;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    final logs = _normalizeLogs(widget.logsRaw)
      ..sort((a, b) {
        final aT = _parseTs(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bT = _parseTs(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aT.compareTo(bT);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${widget.plateNumber} 로그',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: "사진 보기",
                    transitionDuration: const Duration(milliseconds: 300),
                    pageBuilder: (_, __, ___) =>
                        OfflineDepartureCompletedPlateImageDialog(plateNumber: widget.plateNumber),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.black87,
                ),
                child: const Text('사진'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: !_expanded
                ? const Center(
                    key: ValueKey('collapsed'),
                    child: Text('번호판 영역을 눌러 로그를 펼치세요.'),
                  )
                : (logs.isEmpty
                    ? const Center(
                        key: ValueKey('empty'),
                        child: Text('📭 로그가 없습니다.'),
                      )
                    : Scrollbar(
                        key: const ValueKey('list'),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: logs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final e = logs[index];

                            final action = (e['action'] ?? '-').toString();
                            final from = (e['from'] ?? '').toString();
                            final to = (e['to'] ?? '').toString();
                            final performedBy = (e['performedBy'] ?? '').toString();
                            final tsText = _formatTs(e['timestamp']);

                            // 추가: 확정요금/결제수단/사유
                            final String? feeText = (e.containsKey('lockedFee') || e.containsKey('lockedFeeAmount'))
                                ? _formatWon(e['lockedFee'] ?? e['lockedFeeAmount'])
                                : null;
                            final String? payText = (e['paymentMethod']?.toString().trim().isNotEmpty ?? false)
                                ? e['paymentMethod'].toString()
                                : null;
                            final String? reasonText =
                                (e['reason']?.toString().trim().isNotEmpty ?? false) ? e['reason'].toString() : null;

                            final color = _actionColor(action);

                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Icon(_actionIcon(action), color: color),
                              title: Text(action, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (from.isNotEmpty || to.isNotEmpty) Text('$from → $to'),
                                  if (performedBy.isNotEmpty) const SizedBox(height: 2),
                                  if (performedBy.isNotEmpty) const Text('담당자:', style: TextStyle(fontSize: 12)),
                                  if (performedBy.isNotEmpty) Text(performedBy, style: const TextStyle(fontSize: 12)),
                                  if (feeText != null || payText != null || reasonText != null)
                                    const SizedBox(height: 2),
                                  if (feeText != null) Text('확정요금: $feeText', style: const TextStyle(fontSize: 12)),
                                  if (payText != null) Text('결제수단: $payText', style: const TextStyle(fontSize: 12)),
                                  if (reasonText != null) Text('사유: $reasonText', style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                              trailing: Text(tsText, style: const TextStyle(fontSize: 12)),
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
