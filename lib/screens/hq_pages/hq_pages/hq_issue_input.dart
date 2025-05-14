import 'package:flutter/material.dart';

class HqIssueInput extends StatefulWidget {
  const HqIssueInput({super.key});

  @override
  State<HqIssueInput> createState() => _HqIssueInputState();
}

class _HqIssueInputState extends State<HqIssueInput> {
  final TextEditingController _middleReportController = TextEditingController();

  void _handleSubmit() {
    final content = _middleReportController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내용을 입력해주세요.')),
      );
      return;
    }

    // 실제 처리 로직 (예: 서버 전송, 저장 등)
    debugPrint('📨 보고 내용 제출됨: $content');

    // 입력 필드 초기화
    _middleReportController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('보고가 제출되었습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('본사 이슈 입력')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'HQ 이슈 보고란',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _middleReportController,
              decoration: const InputDecoration(
                labelText: '보고란 내용',
                hintText: '예: 특별 상황, 민원, 기타 보고 사항 입력',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _middleReportController.clear(),
                  child: const Text('지우기'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('제출'),
                  onPressed: _handleSubmit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
