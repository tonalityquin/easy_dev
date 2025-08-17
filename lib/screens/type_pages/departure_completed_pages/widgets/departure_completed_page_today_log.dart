import 'package:flutter/material.dart';
import 'plate_image_dialog.dart';

/// TodayLogSection (사진 버튼만 유지, logs 세로 스크롤 표시)
class TodayLogSection extends StatelessWidget {
  const TodayLogSection({
    super.key,
    required this.plateNumber,
    required this.logsRaw, // ← 변경: dynamic 리스트를 받아 내부에서 정규화
  });

  final String plateNumber;
  final List<dynamic> logsRaw;

  List<Map<String, dynamic>> _normalizeLogs(List<dynamic> raw) {
    // Firestore/JSON 등 다양한 런타임 타입을 안전하게 Map<String,dynamic>으로 변환
    return raw.where((e) => e is Map).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String _fmtTime(String? iso) {
    final dt = DateTime.tryParse(iso ?? '')?.toLocal();
    if (dt == null) return '--:--:--';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final logs = _normalizeLogs(logsRaw)
      ..sort((a, b) {
        final aT = DateTime.tryParse('${a['timestamp'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bT = DateTime.tryParse('${b['timestamp'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aT.compareTo(bT); // 오래된 → 최신(오름차순)
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더 + 사진 버튼
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
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade100),
                child: const Text('사진'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 본문: 세로 스크롤
        Expanded(
          child: logs.isEmpty
              ? const Center(child: Text('표시할 로그가 없습니다.'))
              : Scrollbar(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: logs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = logs[index];
                      final action = (e['action'] ?? '-').toString();
                      final timeText = _fmtTime(e['timestamp']?.toString());
                      final from = (e['from'] ?? '').toString();
                      final to = (e['to'] ?? '').toString();
                      final area = (e['area'] ?? '').toString();
                      final performedBy = (e['performedBy'] ?? '').toString();
                      final billingType = e['billingType'];
                      final paymentMethod = e['paymentMethod'];
                      final lockedFee = e['lockedFee'];

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        title: Text(action, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (from.isNotEmpty || to.isNotEmpty) Text('from: $from → to: $to'),
                            if (area.isNotEmpty) Text('area: $area'),
                            if (performedBy.isNotEmpty) Text('by: $performedBy'),
                            if (billingType != null || paymentMethod != null || lockedFee != null)
                              Text(
                                  'billing: ${billingType ?? '-'}, pay: ${paymentMethod ?? '-'}, fee: ${lockedFee ?? '-'}'),
                          ],
                        ),
                        trailing: Text(timeText, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
