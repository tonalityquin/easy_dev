import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/snackbar_helper.dart';

class WorkerDocument extends StatefulWidget {
  const WorkerDocument({Key? key}) : super(key: key);

  @override
  State<WorkerDocument> createState() => _WorkerDocumentState();
}

class _WorkerDocumentState extends State<WorkerDocument>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  String _savedText = '';
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _loadSavedText();
  }

  Future<void> _loadSavedText() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedText = prefs.getString('worker_text') ?? '';
    });
  }

  Future<void> _appendText() async {
    final prefs = await SharedPreferences.getInstance();
    final newText = _controller.text.trim();
    if (newText.isEmpty) return;

    final updatedText = (_savedText + '  ' + newText).trim();
    await prefs.setString('worker_text', updatedText);
    setState(() {
      _savedText = updatedText;
      _controller.clear();
      _menuOpen = false; // ✅ 메뉴 닫기
    });

    showSuccessSnackbar(context, '저장 완료');
  }

  Future<void> _clearText() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('worker_text');
    setState(() {
      _savedText = '';
      _menuOpen = false; // ✅ 메뉴 닫기
    });

    showSuccessSnackbar(context, '전체 삭제 완료');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('직원 문서'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              maxLines: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '추가할 문구 입력',
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '저장된 내용 미리보기 (좌→우 스크롤 가능):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      _savedText,
                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      /// ✅ 하단 FAB + 애니메이션 메뉴
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _menuOpen
                ? Column(
              key: const ValueKey(true),
              children: [
                FloatingActionButton(
                  heroTag: 'saveBtn',
                  mini: true,
                  onPressed: _appendText,
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.save),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'clearBtn',
                  mini: true,
                  onPressed: _clearText,
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.delete),
                ),
                const SizedBox(height: 12),
              ],
            )
                : const SizedBox.shrink(key: ValueKey(false)),
          ),
          FloatingActionButton(
            heroTag: 'mainFab',
            onPressed: () {
              setState(() {
                _menuOpen = !_menuOpen;
              });
            },
            backgroundColor: Colors.blueAccent,
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 300),
              turns: _menuOpen ? 0.25 : 0.0,
              child: const Icon(Icons.more_vert),
            ),
          ),
        ],
      ),
    );
  }
}
