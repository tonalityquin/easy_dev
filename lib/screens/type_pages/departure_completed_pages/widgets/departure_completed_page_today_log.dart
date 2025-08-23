import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'plate_image_dialog.dart';

class TodayLogSection extends StatelessWidget {
  const TodayLogSection({
    super.key,
    required this.plateNumber,
    required this.logsRaw,
  });

  final String plateNumber;
  final List<dynamic> logsRaw;

  // ===== 공통 로직: 로그 정규화 =====
  List<Map<String, dynamic>> _normalizeLogs(List<dynamic> raw) {
    return raw
        .where((e) => e is Map)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ===== 공통 로직: 타임스탬프 파싱 =====
  DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;

    if (ts is Timestamp) return ts.toDate().toLocal();
    if (ts is DateTime) return ts.toLocal();

    if (ts is int) {
      // 밀리초로 보이는 큰 값 처리
      if (ts > 100000000000) return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
      // 초 단위로 가정
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

  Color _actionColor(String action) {
    if (action.contains('사전 정산')) return Colors.teal;
    if (action.contains('출차')) return Colors.orange;
    if (action.contains('취소')) return Colors.redAccent;
    if (action.contains('생성')) return Colors.indigo;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    // 정규화 + PlateLogViewerBottomSheet와 동일하게 "오래된순(오름차순)" 정렬
    final logs = _normalizeLogs(logsRaw)
      ..sort((a, b) {
        final aT = _parseTs(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bT = _parseTs(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aT.compareTo(bT);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더: 타이틀 + 사진 버튼
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$plateNumber 로그',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: "사진 보기",
                    transitionDuration: const Duration(milliseconds: 300),
                    pageBuilder: (_, __, ___) => PlateImageDialog(plateNumber: plateNumber),
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

        // 본문 리스트 (PlateLogViewerBottomSheet와 동일한 타일 구성 + 결제/요금/사유 표시)
        Expanded(
          child: logs.isEmpty
              ? const Center(child: Text('📭 로그가 없습니다.'))
              : Scrollbar(
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
                final String? reasonText = (e['reason']?.toString().trim().isNotEmpty ?? false)
                    ? e['reason'].toString()
                    : null;

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
                      if (performedBy.isNotEmpty)
                        Text('담당자: $performedBy', style: const TextStyle(fontSize: 12)),

                      // 사전 정산 정보 (존재할 때만)
                      if (feeText != null || payText != null || reasonText != null) const SizedBox(height: 2),
                      if (feeText != null)
                        Text('확정요금: $feeText', style: const TextStyle(fontSize: 12)),
                      if (payText != null)
                        Text('결제수단: $payText', style: const TextStyle(fontSize: 12)),
                      if (reasonText != null)
                        Text('사유: $reasonText', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  trailing: Text(tsText, style: const TextStyle(fontSize: 12)),
                  isThreeLine: true,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
