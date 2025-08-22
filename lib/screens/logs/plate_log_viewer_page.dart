import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/plate_log_model.dart';

class PlateLogViewerBottomSheet extends StatefulWidget {
  final String? initialPlateNumber; // 문서 ID를 만들 plateNumber로 사용
  final String division; // (호환성 유지용) 현재는 Firestore 조회에 사용하지 않음
  final String area; // 문서 ID를 만들 때 사용
  final DateTime requestTime; // (호환성 유지용) 현재는 Firestore 조회에 사용하지 않음

  const PlateLogViewerBottomSheet({
    super.key,
    this.initialPlateNumber,
    required this.division,
    required this.area,
    required this.requestTime,
  });

  static Future<void> show(
    BuildContext context, {
    required String division,
    required String area,
    required DateTime requestTime,
    String? initialPlateNumber,
  }) async {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      await Future.delayed(const Duration(milliseconds: 250));
    }

    if (!context.mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierLabel: '닫기',
      transitionDuration: const Duration(milliseconds: 400),
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
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  @override
  State<PlateLogViewerBottomSheet> createState() => _PlateLogViewerBottomSheetState();
}

class _PlateLogViewerBottomSheetState extends State<PlateLogViewerBottomSheet> {
  List<PlateLogModel> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  String _normalize(String? input) => (input ?? '').replaceAll(RegExp(r'[\s\-]'), '').trim();

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final plate = widget.initialPlateNumber;
      if (plate == null || plate.trim().isEmpty) {
        debugPrint('❗ plateNumber가 없어 Firestore 문서 조회 불가');
        if (mounted) {
          setState(() {
            _logs = [];
            _isLoading = false;
          });
        }
        return;
      }

      final docId = '${plate}_${widget.area}';
      final snap = await FirebaseFirestore.instance.collection('plates').doc(docId).get();

      if (!snap.exists) {
        debugPrint('📭 문서 없음: $docId');
        if (mounted) {
          setState(() {
            _logs = [];
            _isLoading = false;
          });
        }
        return;
      }

      final data = snap.data() ?? {};
      final rawLogs = (data['logs'] as List?) ?? const [];

      final logs = <PlateLogModel>[];
      for (final e in rawLogs) {
        if (e is Map) {
          try {
            logs.add(PlateLogModel.fromMap(Map<String, dynamic>.from(e)));
          } catch (err) {
            debugPrint('⚠️ 로그 파싱 실패: $err');
          }
        }
      }

      // 최신순
      logs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      // (옵션) initialPlateNumber로 한 번 더 필터링 — 문서 ID로 이미 특정 plate지만, 안전하게 유지
      final filtered = logs.where((log) {
        if (widget.initialPlateNumber == null) return true;
        return _normalize(log.plateNumber) == _normalize(widget.initialPlateNumber);
      }).toList();

      if (!mounted) return;
      setState(() {
        _logs = filtered;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("❌ Firestore 로그 불러오기 실패: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateTitle = widget.initialPlateNumber != null ? '${widget.initialPlateNumber} 로그' : '번호판 로그';

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
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _logs.isEmpty
                            ? const Center(child: Text("📭 로그가 없습니다."))
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: _logs.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, index) {
                                  final log = _logs[index];
                                  return ListTile(
                                    leading: const Icon(Icons.directions_car),
                                    title: Text(log.action),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${log.from} → ${log.to}'),
                                        Text(
                                          '담당자: ${log.performedBy}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    trailing: Text(
                                      log.timestamp.toString().substring(0, 19),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    isThreeLine: true,
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
