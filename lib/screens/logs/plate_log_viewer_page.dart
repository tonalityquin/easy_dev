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
  LogPlateState? _logState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // dispose에서 사용할 LogPlateState를 안전하게 저장
    _logState ??= context.read<LogPlateState>();
  }

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
      Future.microtask(() => _logState?.clearFilters()); // 👈 안전하게 마이크로태스크로 이동
    }
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final logState = context.watch<LogPlateState>();
    final logs = logState.filteredLogs;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        centerTitle: true,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 4),
            Text(
              logs.isNotEmpty ? logs.first.plateNumber : "번호판 로그",
              style: const TextStyle(color: Colors.black, fontSize: 16),
            ),
            const SizedBox(width: 4),
          ],
        ),
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
            title: Text('${log.action}'),
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
