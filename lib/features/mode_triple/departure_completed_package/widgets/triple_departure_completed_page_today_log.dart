import 'package:flutter/material.dart';

import 'triple_departure_completed_plate_image_dialog.dart';

class TripleTodayLogSection extends StatefulWidget {
  const TripleTodayLogSection({
    super.key,
    required this.plateNumber,
    required this.logsRaw,
  });

  final String plateNumber;
  final List<dynamic> logsRaw;

  @override
  State<TripleTodayLogSection> createState() => _TripleTodayLogSectionState();
}

class _TripleTodayLogSectionState extends State<TripleTodayLogSection> {
  bool _expanded = false;

  
  List<Map<String, dynamic>> _normalizeLogs(List<dynamic> raw) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  
  DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;

    try {
      final dynamic maybeDate = (ts as dynamic).toDate();
      if (maybeDate is DateTime) return maybeDate.toLocal();
    } catch (_) {}

    if (ts is DateTime) return ts.toLocal();

    if (ts is int) {
      if (ts > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
      }
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

  
  
  
  Color _actionColor(BuildContext context, String action) {
    final cs = Theme.of(context).colorScheme;

    if (action.contains('사전 정산')) return cs.primary;
    if (action.contains('출차')) return cs.secondary;
    if (action.contains('취소')) return cs.error;
    if (action.contains('생성')) return cs.tertiary;

    return cs.onSurfaceVariant;
  }

  void _openPhotoDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "사진 보기",
      barrierColor: cs.scrim.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) {
        return TripleDepartureCompletedPlateImageDialog(
          plateNumber: widget.plateNumber,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    
    final logs = _normalizeLogs(widget.logsRaw)
      ..sort((a, b) {
        final aT = _parseTs(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bT = _parseTs(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aT.compareTo(bT);
      });

    final headerTextStyle = theme.textTheme.titleSmall?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
    ) ??
        TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: cs.onSurface,
        );

    final helperTextStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    ) ??
        TextStyle(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${widget.plateNumber} 로그',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: headerTextStyle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              
              OutlinedButton.icon(
                onPressed: () => _openPhotoDialog(context),
                icon: Icon(Icons.photo, color: cs.onSurface),
                label: Text(
                  '사진',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ) ??
                      TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: cs.surfaceContainerLow,
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ).copyWith(
                  overlayColor: MaterialStateProperty.resolveWith<Color?>(
                        (states) => states.contains(MaterialState.pressed)
                        ? cs.outlineVariant.withOpacity(0.12)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),

        
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
                style: helperTextStyle,
                textAlign: TextAlign.center,
              ),
            )
                : (logs.isEmpty
                ? Center(
              key: const ValueKey('empty'),
              child: Text(
                '📭 로그가 없습니다.',
                style: helperTextStyle,
                textAlign: TextAlign.center,
              ),
            )
                : Scrollbar(
              key: const ValueKey('list'),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: logs.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: cs.outlineVariant.withOpacity(0.55),
                ),
                itemBuilder: (context, index) {
                  final e = logs[index];

                  final action = (e['action'] ?? '-').toString();
                  final from = (e['from'] ?? '').toString();
                  final to = (e['to'] ?? '').toString();
                  final performedBy = (e['performedBy'] ?? '').toString();
                  final tsText = _formatTs(e['timestamp']);

                  
                  final String? feeText =
                  (e.containsKey('lockedFee') || e.containsKey('lockedFeeAmount'))
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

                  final titleStyle = theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ) ??
                      TextStyle(
                        fontWeight: FontWeight.w800,
                        color: color,
                      );

                  final metaStyle = theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ) ??
                      TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      );

                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Icon(_actionIcon(action), color: color),
                    title: Text(action, style: titleStyle),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (from.isNotEmpty || to.isNotEmpty)
                          Text('$from → $to', style: metaStyle),
                        if (performedBy.isNotEmpty) const SizedBox(height: 2),
                        if (performedBy.isNotEmpty)
                          Text('담당자:', style: metaStyle),
                        if (performedBy.isNotEmpty)
                          Text(performedBy, style: metaStyle),
                        if (feeText != null || payText != null || reasonText != null)
                          const SizedBox(height: 2),
                        if (feeText != null)
                          Text('확정요금: $feeText', style: metaStyle),
                        if (payText != null)
                          Text('결제수단: $payText', style: metaStyle),
                        if (reasonText != null)
                          Text('사유: $reasonText', style: metaStyle),
                      ],
                    ),
                    trailing: Text(
                      tsText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ) ??
                          TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
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
