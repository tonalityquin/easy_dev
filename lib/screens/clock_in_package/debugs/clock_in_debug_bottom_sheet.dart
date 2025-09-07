import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../../../utils/snackbar_helper.dart';
import 'clock_in_debug_firestore_logger.dart';

/// Firestore 로그 디버깅 바텀시트
/// - 로그 보기, 검색, 복사, 내보내기, 삭제 기능 제공
class ClockInDebugBottomSheet extends StatefulWidget {
  const ClockInDebugBottomSheet({super.key});

  @override
  State<ClockInDebugBottomSheet> createState() => _ClockInDebugBottomSheetState();
}

class _ClockInDebugBottomSheetState extends State<ClockInDebugBottomSheet> {
  List<String> _logLines = []; // 전체 로그
  List<String> _filteredLines = []; // 필터링된 로그
  bool _isLoading = true;

  final DateFormat _timestampFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _loadLog(); // 파일에서 로그 불러오기
  }

  /// 로그 파일 로드 및 상태 갱신
  Future<void> _loadLog() async {
    final text = await ClockInDebugFirestoreLogger().readLog();
    setState(() {
      _isLoading = false;

      if (text.isEmpty) {
        _logLines = ['🚫 저장된 로그가 없습니다.'];
      } else {
        _logLines =
            text.trim().split('\n').where((line) => line.trim().isNotEmpty).toList().reversed.toList(); // 최신 로그 위로
      }

      _filteredLines = List.from(_logLines);
    });
  }

  /// 검색어 기준으로 로그 필터링
  void _filterLogs(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredLines = List.from(_logLines);
      } else {
        _filteredLines = _logLines.where((line) => line.toLowerCase().contains(query.toLowerCase())).toList();
      }
    });
  }

  /// 로그 전체 삭제
  Future<void> _clearLog() async {
    await ClockInDebugFirestoreLogger().clearLog();
    await _loadLog();

    if (context.mounted) {
      // ✅ 기존 SnackBar → 커스텀 스낵바
      showSuccessSnackbar(context, '로그가 삭제되었습니다.');
    }
  }

  /// 로그 파일 내보내기 (공유)
  Future<void> _exportLogFile() async {
    final file = ClockInDebugFirestoreLogger().getLogFile();

    if (file == null || !await file.exists()) {
      if (context.mounted) {
        // ✅ 실패 시 커스텀 스낵바
        showFailedSnackbar(context, '내보낼 로그 파일이 없습니다.');
      }
      return;
    }

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Firestore 로그 파일',
      subject: 'Firestore 로그',
    );
  }

  /// 현재 필터링된 로그를 클립보드에 복사
  Future<void> _copyLogsToClipboard() async {
    final allLogs = _filteredLines.reversed.join('\n');
    await Clipboard.setData(ClipboardData(text: allLogs));

    if (context.mounted) {
      // ✅ 성공 시 커스텀 스낵바
      showSuccessSnackbar(context, '로그가 클립보드에 복사되었습니다.');
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

            // 검색창 및 기능 버튼들
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  // 검색 필드
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

                  // 로그 내보내기 버튼
                  IconButton(
                    onPressed: _exportLogFile,
                    icon: const Icon(Icons.upload_file, color: Colors.blueGrey),
                    tooltip: '로그 파일 내보내기',
                  ),

                  // 복사 버튼
                  IconButton(
                    onPressed: _copyLogsToClipboard,
                    icon: const Icon(Icons.copy, color: Colors.teal),
                    tooltip: '로그 복사',
                  ),

                  // 삭제 버튼
                  IconButton(
                    onPressed: _clearLog,
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    tooltip: '전체 로그 삭제',
                  ),
                ],
              ),
            ),

            // 안내 텍스트
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '✅: 성공 | 🔥/error: 오류 | called: 실행 | 기타: 정보',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),

            const Divider(height: 1),

            // 본문 로그 리스트
            Expanded(
              child: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildLogList(),
            ),
          ],
        ),
      ),
    );
  }

  /// 로그 리스트 렌더링
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

          // 로그 파싱: [timestamp] : [message]
          if (parts.length >= 2) {
            timestampStr = parts.first;
            message = parts.sublist(1).join(': ');
          }

          // 타임스탬프 포맷 변환
          String datePart = '';
          String timePart = '';
          try {
            final dt = DateTime.parse(timestampStr);
            final formatted = _timestampFormat.format(dt);
            final split = formatted.split(' ');
            datePart = split[0];
            timePart = split[1];
          } catch (_) {}

          // 메시지 기반 색상 및 아이콘 지정
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

          // 로그 한 줄 UI
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),

                // 날짜 및 시간
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

                // 로그 메시지 본문
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
