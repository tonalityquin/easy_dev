import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/plate_log_model.dart';

class PlateLogViewerBottomSheet extends StatefulWidget {
  /// plateNumber (문서 ID 폴백 조합에 사용)
  final String? initialPlateNumber;

  /// 현재 Firestore 조회에는 사용하지 않지만 호환성 유지를 위해 남겨둠
  final String division;

  /// 문서 ID 폴백 조합에 사용
  final String area;

  /// 호환성 유지를 위해 남겨둠 (조회에는 사용하지 않음)
  final DateTime requestTime;

  /// 가능하면 실제 Firestore 문서 ID를 넘겨주세요 (가장 정확)
  final String? plateId;

  const PlateLogViewerBottomSheet({
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
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (!context.mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierLabel: '닫기',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) {
        return Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: PlateLogViewerBottomSheet(
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
  State<PlateLogViewerBottomSheet> createState() => _PlateLogViewerBottomSheetState();
}

class _PlateLogViewerBottomSheetState extends State<PlateLogViewerBottomSheet> {
  /// true: 최신순, false: 오래된순
  bool _desc = false;

  String _buildDocId() {
    // 1순위: plateId 직접 제공
    final pid = widget.plateId?.trim();
    if (pid != null && pid.isNotEmpty) return pid;

    // 2순위: plateNumber_area 규칙
    final p = widget.initialPlateNumber?.trim() ?? '';
    final a = widget.area.trim();
    return '${p}_$a';
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _docStream(String docId) {
    return FirebaseFirestore.instance.collection('plates').doc(docId).snapshots();
  }

  // ✅ intl 없이 직접 포맷팅 (KST 등 로컬 타임존으로 표시)
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

  List<PlateLogModel> _parseLogs(List raw) {
    final logs = <PlateLogModel>[];
    for (final e in raw) {
      if (e is Map) {
        try {
          logs.add(PlateLogModel.fromMap(Map<String, dynamic>.from(e)));
        } catch (err) {
          debugPrint('⚠️ 로그 파싱 실패: $err');
        }
      }
    }
    return logs;
  }

  void _applySort(List<PlateLogModel> logs) {
    logs.sort((a, b) => _desc ? b.timestamp.compareTo(a.timestamp) : a.timestamp.compareTo(b.timestamp));
  }

  @override
  Widget build(BuildContext context) {
    final plateTitle = widget.initialPlateNumber != null ? '${widget.initialPlateNumber} 로그' : '번호판 로그';
    final docId = _buildDocId();

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.list_alt, color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              plateTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 정렬 토글
                          TextButton.icon(
                            onPressed: () => setState(() => _desc = !_desc),
                            icon: Icon(_desc ? Icons.south : Icons.north, size: 18),
                            label: Text(_desc ? '최신순' : '오래된순'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[800],
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _docStream(docId),
                        builder: (_, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snap.hasError) {
                            return const _ErrorState(
                              message: '로그를 불러오는 중 오류가 발생했습니다.',
                            );
                          }
                          final doc = snap.data;
                          if (doc == null || !doc.exists) {
                            return const _EmptyState(text: '📭 문서를 찾을 수 없습니다.');
                          }
                          final data = doc.data() ?? {};
                          final rawLogs = (data['logs'] as List?) ?? const [];
                          final logs = _parseLogs(rawLogs);
                          if (logs.isEmpty) {
                            return const _EmptyState(text: '📭 로그가 없습니다.');
                          }
                          _applySort(logs);

                          return ListView.separated(
                            controller: scrollController,
                            itemCount: logs.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final log = logs[index];
                              final tsText = _formatTs(log.timestamp);
                              final color = _actionColor(log.action);
                              return ListTile(
                                leading: Icon(_actionIcon(log.action), color: color),
                                title: Text(log.action, style: TextStyle(color: color)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (log.from.isNotEmpty || log.to.isNotEmpty) Text('${log.from} → ${log.to}'),
                                    if (log.performedBy.isNotEmpty) const SizedBox(height: 2),
                                    if (log.performedBy.isNotEmpty)
                                      Text('담당자: ${log.performedBy}', style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                                trailing: Text(tsText, style: const TextStyle(fontSize: 12)),
                                isThreeLine: true,
                                dense: true,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(text, style: const TextStyle(color: Colors.grey)),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(message, style: const TextStyle(color: Colors.redAccent)),
      ),
    );
  }
}
