import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/break_log_state.dart'; // 생성한 로그 상태

class WorkerManagementPage extends StatelessWidget {
  const WorkerManagementPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('휴게시간 기록'),
        centerTitle: true,
      ),
      body: Consumer<BreakLogState>(
        builder: (context, logState, _) {
          if (logState.logs.isEmpty) {
            return const Center(child: Text('기록이 없습니다.'));
          }
          return ListView.builder(
            itemCount: logState.logs.length,
            itemBuilder: (context, index) {
              final log = logState.logs[index];
              final time = TimeOfDay.fromDateTime(log.timestamp);
              final date = '${log.timestamp.year}-${log.timestamp.month.toString().padLeft(2, '0')}-${log.timestamp.day.toString().padLeft(2, '0')}';
              return ListTile(
                title: Text(log.name),
                subtitle: Text('$date ${time.format(context)}'),
              );
            },
          );
        },
      ),
    );
  }
}
