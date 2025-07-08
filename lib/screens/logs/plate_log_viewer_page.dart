import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

import '../../models/plate_log_model.dart';

class PlateLogViewerBottomSheet extends StatefulWidget {
  final String? initialPlateNumber;
  final String division;
  final String area;
  final DateTime requestTime;

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
    // ✅ 중복 방지: 기존 화면이 있으면 닫고 잠시 대기
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      await Future.delayed(const Duration(milliseconds: 250));
    }

    // ✅ mounted 체크
    if (!context.mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierLabel: '닫기',
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) {
        return Material(
          color: Colors.transparent, // ✅ 중요!
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
  State<PlateLogViewerBottomSheet> createState() =>
      _PlateLogViewerBottomSheetState();
}

class _PlateLogViewerBottomSheetState
    extends State<PlateLogViewerBottomSheet> {
  final String bucketName = 'easydev-image';
  final String serviceAccountPath =
      'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  List<PlateLogModel> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  String _normalize(String? input) =>
      (input ?? '').replaceAll(RegExp(r'[\s\-]'), '').trim();

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final credentialsJson = await rootBundle.loadString(serviceAccountPath);
      final accountCredentials =
      ServiceAccountCredentials.fromJson(credentialsJson);
      final scopes = [StorageApi.devstorageReadOnlyScope];
      final client =
      await clientViaServiceAccount(accountCredentials, scopes);
      final storage = StorageApi(client);

      final year = widget.requestTime.year.toString();
      final month = widget.requestTime.month.toString().padLeft(2, '0');
      final day = widget.requestTime.day.toString().padLeft(2, '0');
      final prefix =
          '${widget.division}/${widget.area}/$year/$month/$day/logs/';

      final objects = await storage.objects.list(bucketName, prefix: prefix);
      final logFiles = objects.items
          ?.where((o) => o.name?.endsWith('.json') ?? false)
          .toList() ??
          [];

      final logs = <PlateLogModel>[];
      for (final file in logFiles) {
        final uri =
        Uri.parse('https://storage.googleapis.com/$bucketName/${file.name}');
        final response = await NetworkAssetBundle(uri).load('');
        final jsonString = utf8.decode(response.buffer.asUint8List());
        final jsonMap = jsonDecode(jsonString);
        final log = PlateLogModel.fromMap(jsonMap);
        logs.add(log);
      }

      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final filtered = widget.initialPlateNumber != null
          ? logs
          .where((log) =>
      _normalize(log.plateNumber) ==
          _normalize(widget.initialPlateNumber))
          .toList()
          : logs;

      if (!mounted) return;

      setState(() {
        _logs = filtered;
        _isLoading = false;
      });

      client.close();
    } catch (e) {
      debugPrint("❌ 로그 불러오기 실패: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateTitle = widget.initialPlateNumber != null
        ? '${widget.initialPlateNumber} 로그'
        : '번호판 로그';

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
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
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

                  // Body
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _logs.isEmpty
                        ? const Center(child: Text("📭 로그가 없습니다."))
                        : ListView.separated(
                      controller: scrollController,
                      itemCount: _logs.length,
                      separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final log = _logs[index];
                        return ListTile(
                          leading: const Icon(Icons.directions_car),
                          title: Text(log.action),
                          subtitle: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text('${log.from} → ${log.to}'),
                              Text(
                                '담당자: ${log.performedBy}',
                                style:
                                const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          trailing: Text(
                            log.timestamp
                                .toString()
                                .substring(0, 19),
                            style:
                            const TextStyle(fontSize: 12),
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
                  ),

                  // Footer
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
