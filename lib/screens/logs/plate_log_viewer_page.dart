import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate/log_plate.dart';

class PlateLogViewerPage extends StatefulWidget {
  final String? initialPlateNumber;

  const PlateLogViewerPage({
    super.key,
    this.initialPlateNumber,
  });

  @override
  State<PlateLogViewerPage> createState() => _PlateLogViewerPageState();
}

class _PlateLogViewerPageState extends State<PlateLogViewerPage> {
  bool _appliedInitialFilter = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final logState = context.read<LogPlateState>();

      if (widget.initialPlateNumber != null) {
        final normalized = widget.initialPlateNumber!.replaceAll(RegExp(r'[-\s]'), '');
        debugPrint('[DEBUG] 초기 필터 적용: $normalized');
        logState.setFilterPlateNumber(normalized);
        _appliedInitialFilter = true;
      } else {
        debugPrint('[DEBUG] 초기 번호판 필터 없음');
      }
    });
  }

  @override
  void dispose() {
    if (_appliedInitialFilter) {
      debugPrint('[DEBUG] PlateLogViewerPage 종료 - 필터 초기화');
      context.read<LogPlateState>().clearFilters();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logState = context.watch<LogPlateState>();
    final logs = logState.filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: const Text("번호판 로그 기록"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              logState.clearFilters(); // ✅ 번호판 필터 초기화
            },
          ),
        ],
      ),
      body: logState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : logs.isEmpty
          ? const Center(child: Text("해당 조건의 로그가 없습니다."))
          : ListView.separated(
        itemCount: logs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final log = logs[index];
          return ListTile(
            leading: const Icon(Icons.directions_car),
            title: Text('${log.plateNumber} | ${log.action}'),
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
    );
  }
}
