import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_panel.dart'; // ChatPanel이 정의된 파일

void chatBottomSheet(BuildContext context) {
  final TextEditingController _fileIdInputController = TextEditingController();

  String? fileId;
  List<String> fileIdHistory = [];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> loadPrefs() async {
            final prefs = await SharedPreferences.getInstance();
            final savedId = prefs.getString('chat_file_id');
            final history = prefs.getStringList('chat_file_id_history') ?? [];

            fileId = (savedId != null && savedId.isNotEmpty)
                ? savedId
                : '1RlsEmXGlf7sK57B-ITEewiFBLg8GOeLD';

            fileIdHistory = history.toSet().toList();
            setState(() {});
          }

          Future<void> saveFileId(String id) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('chat_file_id', id);
            final updatedHistory = [id, ...fileIdHistory.where((e) => e != id)].take(5).toList();
            await prefs.setStringList('chat_file_id_history', updatedHistory);
            fileId = id;
            fileIdHistory = updatedHistory;
            setState(() {});
          }

          Future<void> clearFileId() async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('chat_file_id');
            fileId = null;
            setState(() {});
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (fileId == null) loadPrefs();
          });

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 상단 타이틀과 링크 버튼
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 48),
                      const Expanded(
                        child: Center(
                          child: Text(
                            '구역 채팅',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.link),
                        tooltip: '구글 드라이브 ID 설정',
                        onPressed: () {
                          showDialog(
                            context: ctx,
                            builder: (_) => AlertDialog(
                              title: const Text('Google Drive JSON ID 연결'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: _fileIdInputController,
                                    decoration: const InputDecoration(hintText: '예: 1RlsEmXG...'),
                                  ),
                                  const SizedBox(height: 12),
                                  if (fileIdHistory.isNotEmpty)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('최근 사용한 ID'),
                                        ...fileIdHistory.map((id) => ListTile(
                                          dense: true,
                                          title: Text(id),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            saveFileId(id);
                                          },
                                        )),
                                      ],
                                    ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    clearFileId();
                                    _fileIdInputController.clear();
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('초기화'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('취소'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    final newId = _fileIdInputController.text.trim();
                                    if (newId.isNotEmpty) {
                                      saveFileId(newId);
                                    }
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('적용'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 채팅 영역
                  if (fileId == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '채팅창을 연결하세요.',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  else
                    ChatPanel(fileId: fileId!), // ✅ ChatPanel 적용
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
