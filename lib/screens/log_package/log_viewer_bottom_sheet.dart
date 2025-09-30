import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/plate_log_model.dart';
// import '../../utils/usage_reporter.dart';

class LogViewerBottomSheet extends StatefulWidget {
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
  /// true: 최신순, false: 오래된순 (기본: 오래된순)
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
    // 1순위: plateId 직접 제공
    final pid = widget.plateId?.trim();
    if (pid != null && pid.isNotEmpty) return pid;

    // 2순위: plateNumber_area 규칙
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

      // 현재 원하는 정렬(_desc)에 맞춰 "한 번만" 정렬하고 상태 플래그 갱신
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
    } finally {
      try {
        /*await UsageReporter.instance.report(
          area: (widget.area.isEmpty ? 'unknown' : widget.area),
          action: 'read',
          n: 1,
          source: 'LogViewerBottomSheet._loadLogs/plates.doc.get',
        );*/
      } catch (_) {
      }
    }
  }

  // intl 없이 직접 포맷팅(로컬 타임존)
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

  // 원화 간단 포맷 (intl 없이 콤마만)
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

  Color _actionColor(String action) {
    if (action.contains('사전 정산')) return Colors.teal;
    if (action.contains('출차')) return Colors.orange;
    if (action.contains('취소')) return Colors.redAccent;
    if (action.contains('생성')) return Colors.indigo;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    final plateTitle = widget.initialPlateNumber != null ? '${widget.initialPlateNumber} 로그' : '번호판 로그';

    // ★ 풀스크린 화이트 시트
    final size = MediaQuery.of(context).size;

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: size.height, // 화면 전체 높이
            width: double.infinity,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white, // 전면 흰 배경
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 16,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Column(
                  children: [
                    // 드래그 핸들 + 헤더
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
                          // 정렬 토글 (불필요한 재정렬 없이 reverse만 수행)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _desc = !_desc; // 원하는 정렬 상태 변경
                                _logs = _logs.reversed.toList(); // 리스트 뒤집기만
                              });
                            },
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

                    // 콘텐츠
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : (_errorMessage != null)
                              ? _ErrorState(message: _errorMessage!)
                              : (_logs.isEmpty)
                                  ? const _EmptyState(text: '📭 로그가 없습니다.')
                                  : ListView.separated(
                                      itemCount: _logs.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (_, index) {
                                        final log = _logs[index];
                                        final tsText = _formatTs(log.timestamp);
                                        final color = _actionColor(log.action);

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
                                            style: TextStyle(color: color),
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
                                                ),
                                              if (log.performedBy.isNotEmpty) const SizedBox(height: 2),
                                              if (log.performedBy.isNotEmpty)
                                                Text(
                                                  '담당자: ${log.performedBy}',
                                                  style: const TextStyle(fontSize: 12),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),

                                              // 사전 정산 관련 정보 (있을 때만 표시)
                                              if (feeText != null || payText != null || reasonText != null)
                                                const SizedBox(height: 2),
                                              if (feeText != null)
                                                Text('확정요금: $feeText', style: const TextStyle(fontSize: 12)),
                                              if (payText != null)
                                                Text('결제수단: $payText', style: const TextStyle(fontSize: 12)),
                                              if (reasonText != null)
                                                Text('사유: $reasonText',
                                                    style: const TextStyle(fontSize: 12),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                          trailing: Text(tsText, style: const TextStyle(fontSize: 12)),
                                          isThreeLine: true,
                                          dense: true,
                                        );
                                      },
                                    ),
                    ),

                    // 하단 액션
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton.icon(
                        onPressed: _loadLogs, // 필요할 때만 네트워크 읽기
                        icon: const Icon(Icons.refresh),
                        label: const Text("새로고침"),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
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
