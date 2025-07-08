import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'secondary_debug_firestore_logger.dart';

class SecondaryDebugBottomSheet extends StatefulWidget {
  const SecondaryDebugBottomSheet({super.key});

  @override
  State<SecondaryDebugBottomSheet> createState() => _SecondaryDebugBottomSheetState();
}

class _SecondaryDebugBottomSheetState extends State<SecondaryDebugBottomSheet> {
  List<String> _logLines = [];
  List<String> _filteredLines = [];
  bool _isLoading = true;

  final DateFormat _timestampFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _loadLog();
  }

  Future<void> _loadLog() async {
    final text = await SecondaryDebugFirestoreLogger().readLog();
    setState(() {
      _isLoading = false;
      if (text.isEmpty) {
        _logLines = ['🚫 저장된 로그가 없습니다.'];
      } else {
        _logLines = text
            .trim()
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList()
            .reversed
            .toList();
      }
      _filteredLines = List.from(_logLines);
    });
  }

  void _filterLogs(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredLines = List.from(_logLines);
      } else {
        _filteredLines = _logLines
            .where((line) => line.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _clearLog() async {
    await SecondaryDebugFirestoreLogger().clearLog();
    await _loadLog();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그가 삭제되었습니다.')),
      );
    }
  }

  Future<void> _exportLogFile() async {
    final file = SecondaryDebugFirestoreLogger().getLogFile();
    if (file == null || !await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('내보낼 로그 파일이 없습니다.')),
        );
      }
      return;
    }

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Firestore 로그 파일',
      subject: 'Firestore 로그',
    );
  }

  Future<void> _copyLogsToClipboard() async {
    final allLogs = _filteredLines.reversed.join('\n');
    await Clipboard.setData(ClipboardData(text: allLogs));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그가 클립보드에 복사되었습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: SafeArea(
        child: Column(
          children: [
            // 상단 헤더
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Firestore 로그',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            // 검색창 + 아이콘 버튼들
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: '검색어를 입력하세요',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: _filterLogs,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _exportLogFile,
                    icon: const Icon(Icons.upload_file, color: Colors.blueGrey),
                    tooltip: '로그 파일 내보내기',
                  ),
                  IconButton(
                    onPressed: _copyLogsToClipboard,
                    icon: const Icon(Icons.copy, color: Colors.teal),
                    tooltip: '로그 복사',
                  ),
                  IconButton(
                    onPressed: _clearLog,
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    tooltip: '전체 로그 삭제',
                  ),
                ],
              ),
            ),
            // 색상/아이콘 안내
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '✅: 성공 | 🔥/error: 오류 | called: 실행 | 기타: 정보',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildLogList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogList() {
    return Scrollbar(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _filteredLines.length,
        itemBuilder: (context, index) {
          final line = _filteredLines[index];
          final parts = line.split(': ');
          String timestampStr = '';
          String message = line;

          if (parts.length >= 2) {
            timestampStr = parts.first;
            message = parts.sublist(1).join(': ');
          }

          // 타임스탬프 포맷
          String datePart = '';
          String timePart = '';
          try {
            final dt = DateTime.parse(timestampStr);
            final formatted = _timestampFormat.format(dt);
            final split = formatted.split(' ');
            datePart = split[0];
            timePart = split[1];
          } catch (_) {}

          // 색상/아이콘 결정
          final lcMessage = message.toLowerCase();
          Color color = Colors.black;
          IconData icon = Icons.info;

          if (lcMessage.contains('[error]') || lcMessage.contains('🔥')) {
            color = Colors.redAccent;
            icon = Icons.error;
          } else if (lcMessage.contains('[success]') || lcMessage.contains('✅')) {
            color = Colors.green;
            icon = Icons.check_circle;
          } else if (lcMessage.contains('[called]')) {
            color = Colors.blueAccent;
            icon = Icons.play_arrow;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      datePart,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      timePart,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      color: color,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
