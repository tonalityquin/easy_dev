import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TodayField extends StatefulWidget {
  const TodayField({super.key});

  @override
  State<TodayField> createState() => _TodayFieldState();
}

class _TodayFieldState extends State<TodayField> {
  final TextEditingController _controller = TextEditingController();
  static const String _memoListKey = 'memo_list';
  List<String> _memoList = [];

  @override
  void initState() {
    super.initState();
    _loadMemoList();
  }

  Future<void> _loadMemoList() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _memoList = prefs.getStringList(_memoListKey) ?? [];
    });
  }

  Future<void> _saveMemo() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _memoList.insert(0, text); // 최신 메모가 위로 오도록
      _controller.clear();
    });
    await prefs.setStringList(_memoListKey, _memoList);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('메모가 저장되었습니다')),
    );
  }

  Future<void> _clearMemos() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _memoList.clear();
    });
    await prefs.remove(_memoListKey);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('모든 메모가 삭제되었습니다')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘의 메모'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveMemo,
            tooltip: '저장',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearMemos,
            tooltip: '삭제',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              maxLines: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '오늘의 메모를 입력하세요...',
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '저장된 메모',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _memoList.isEmpty
                  ? const Center(child: Text('저장된 메모가 없습니다.'))
                  : ListView.builder(
                itemCount: _memoList.length,
                itemBuilder: (context, index) {
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text(
                        _memoList[index],
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
