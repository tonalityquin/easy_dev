import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

import '../../models/plate_log_model.dart';

class PlateLogViewerPage extends StatefulWidget {
  final String? initialPlateNumber;
  final String division;
  final String area;

  const PlateLogViewerPage({
    super.key,
    this.initialPlateNumber,
    required this.division,
    required this.area,
  });

  @override
  State<PlateLogViewerPage> createState() => _PlateLogViewerPageState();
}

class _PlateLogViewerPageState extends State<PlateLogViewerPage> {
  final String bucketName = 'easydev-image';
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

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
      final credentialsJson = await rootBundle.loadString(serviceAccountPath);
      final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final scopes = [StorageApi.devstorageReadOnlyScope];
      final client = await clientViaServiceAccount(accountCredentials, scopes);
      final storage = StorageApi(client);

      // ✅ 날짜 경로 포함: 2025/05/11
      final year = '2025';
      final month = '05';
      final day = '11';
      final prefix = '${widget.division}/${widget.area}/$year/$month/$day/logs/';

      final objects = await storage.objects.list(bucketName, prefix: prefix);
      final logFiles = objects.items?.where((o) => o.name?.endsWith('.json') ?? false).toList() ?? [];

      final logs = <PlateLogModel>[];

      for (final file in logFiles) {
        final uri = Uri.parse('https://storage.googleapis.com/$bucketName/${file.name}');
        final response = await NetworkAssetBundle(uri).load('');
        final jsonString = utf8.decode(response.buffer.asUint8List());
        final jsonMap = jsonDecode(jsonString);
        final log = PlateLogModel.fromMap(jsonMap);
        logs.add(log);
      }

      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // 최신순

      // ✅ 정규화된 비교 적용
      final filtered = widget.initialPlateNumber != null
          ? logs.where((log) => _normalize(log.plateNumber) == _normalize(widget.initialPlateNumber)).toList()
          : logs;

      setState(() {
        _logs = filtered;
        _isLoading = false;
      });

      client.close();
    } catch (e) {
      debugPrint("❌ 로그 불러오기 실패: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateTitle = widget.initialPlateNumber != null ? '${widget.initialPlateNumber} 로그' : '번호판 로그';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        centerTitle: true,
        title: Text(
          plateTitle,
          style: const TextStyle(color: Colors.black, fontSize: 16),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(child: Text("📭 로그가 없습니다."))
              : ListView.separated(
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
                          Text('담당자: ${log.performedBy}', style: const TextStyle(fontSize: 12)),
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
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton.icon(
          onPressed: _loadLogs,
          icon: const Icon(Icons.refresh),
          label: const Text("새로고침"),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}
