import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/plate_log_model.dart';

class LogViewerBottomSheet extends StatefulWidget {
  final String? initialPlateNumber;
  final String division;
  final String area;
  final DateTime requestTime;
  final String? plateId;

  const LogViewerBottomSheet({
    super.key,
    this.initialPlateNumber,
    required this.division,
    required this.area,
    required this.requestTime,
    this.plateId,
  });

  static Future<void> show(
      BuildContext context, {
        required String division,
        required String area,
        required DateTime requestTime,
        String? initialPlateNumber,
        String? plateId,
      }) async {
    final cs = Theme.of(context).colorScheme;

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (!context.mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: cs.scrim.withOpacity(0.55),
      barrierLabel: '닫기',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) {
        return Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: LogViewerBottomSheet(
              division: division,
              area: area,
              requestTime: requestTime,
              initialPlateNumber: initialPlateNumber,
              plateId: plateId,
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  @override
  State<LogViewerBottomSheet> createState() => _LogViewerBottomSheetState();
}

class _LogViewerBottomSheetState extends State<LogViewerBottomSheet> {
  static const String screenTag = 'plate log';

  bool _desc = false;

  bool _isLoading = true;
  String? _errorMessage;
  List<PlateLogModel> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  String _buildDocId() {
    final pid = widget.plateId?.trim();
    if (pid != null && pid.isNotEmpty) return pid;

    final p = widget.initialPlateNumber?.trim() ?? '';
    final a = widget.area.trim();

    if (p.isEmpty || a.isEmpty) {
      throw StateError('plateId 또는 (initialPlateNumber + area)이 필요합니다.');
    }
    return '${p}_$a';
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final docId = _buildDocId();
      final snap = await FirebaseFirestore.instance.collection('plates').doc(docId).get();

      if (!snap.exists) {
        setState(() {
          _logs = [];
          _isLoading = false;
          _errorMessage = '문서를 찾을 수 없습니다.';
        });
        return;
      }

      final data = snap.data() ?? {};
      final rawLogs = (data['logs'] as List?) ?? const [];

      final logs = <PlateLogModel>[];
      int failed = 0;
      for (final e in rawLogs) {
        if (e is Map) {
          try {
            logs.add(PlateLogModel.fromMap(Map<String, dynamic>.from(e)));
          } catch (err) {
            failed++;
            debugPrint('⚠️ 로그 파싱 실패[$failed]: $err');
          }
        }
      }

      logs.sort((a, b) => _desc ? b.timestamp.compareTo(a.timestamp) : a.timestamp.compareTo(b.timestamp));

      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } on FirebaseException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '로그를 불러오는 중 오류가 발생했습니다. (${e.code}: ${e.message})';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e is StateError ? e.message : '로그를 불러오는 중 오류가 발생했습니다. ($e)';
      });
    }
  }

  String _formatTs(dynamic ts) {
    DateTime? dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is DateTime) {
      dt = ts;
    } else {
      dt = DateTime.tryParse(ts.toString());
    }
    if (dt == null) return ts.toString();
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
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
    if (value == null) return '-';
    final n = (value is num) ? value.toInt() : int.tryParse(value.toString());
    if (n == null) return value.toString();
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

  Color _actionColor(ColorScheme cs, String action) {
    if (action.contains('사전 정산')) return cs.tertiary;
    if (action.contains('출차')) return cs.primary;
    if (action.contains('취소')) return cs.error;
    if (action.contains('생성')) return cs.primary;
    return cs.onSurfaceVariant;
  }

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: Semantics(
            label: 'screen_tag: $screenTag',
            child: Text(screenTag, style: style),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plateTitle = widget.initialPlateNumber != null ? '${widget.initialPlateNumber} 로그' : '번호판 로그';

    final size = MediaQuery.of(context).size;

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: size.height,
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.10),
                    blurRadius: 16,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Column(
                  children: [
                    // 드래그 핸들
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // 화면 태그
                    _buildScreenTag(context),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          Icon(Icons.list_alt, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              plateTitle,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: cs.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _desc = !_desc;
                                _logs = _logs.reversed.toList();
                              });
                            },
                            icon: Icon(_desc ? Icons.south : Icons.north, size: 18),
                            label: Text(_desc ? '최신순' : '오래된순'),
                            style: TextButton.styleFrom(
                              foregroundColor: cs.onSurface,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: cs.onSurface),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),

                    Expanded(
                      child: _isLoading
                          ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                        ),
                      )
                          : (_errorMessage != null)
                          ? _ErrorState(message: _errorMessage!)
                          : (_logs.isEmpty)
                          ? const _EmptyState(text: '📭 로그가 없습니다.')
                          : ListView.separated(
                        itemCount: _logs.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.65)),
                        itemBuilder: (_, index) {
                          final log = _logs[index];
                          final tsText = _formatTs(log.timestamp);
                          final color = _actionColor(cs, log.action);

                          final String? feeText =
                          (log.lockedFee != null) ? _formatWon(log.lockedFee) : null;
                          final String? payText =
                          (log.paymentMethod != null && log.paymentMethod!.trim().isNotEmpty)
                              ? log.paymentMethod
                              : null;
                          final String? reasonText =
                          (log.reason != null && log.reason!.trim().isNotEmpty) ? log.reason : null;

                          return ListTile(
                            leading: Icon(_actionIcon(log.action), color: color),
                            title: Text(
                              log.action,
                              style: TextStyle(color: color, fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (log.from.isNotEmpty || log.to.isNotEmpty)
                                  Text(
                                    '${log.from} → ${log.to}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                if (log.performedBy.isNotEmpty) const SizedBox(height: 2),
                                if (log.performedBy.isNotEmpty)
                                  Text(
                                    '담당자: ${log.performedBy}',
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (feeText != null || payText != null || reasonText != null)
                                  const SizedBox(height: 2),
                                if (feeText != null)
                                  Text('확정요금: $feeText', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                if (payText != null)
                                  Text('결제수단: $payText', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                if (reasonText != null)
                                  Text(
                                    '사유: $reasonText',
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: Text(tsText, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                            isThreeLine: true,
                            dense: true,
                          );
                        },
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton.icon(
                        onPressed: _loadLogs,
                        icon: const Icon(Icons.refresh),
                        label: const Text("새로고침"),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;

  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(message, style: TextStyle(color: cs.error)),
      ),
    );
  }
}
