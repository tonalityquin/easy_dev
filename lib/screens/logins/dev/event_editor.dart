import 'package:flutter/material.dart';

class EventEditorResult {
  final String title;
  final DateTime start;
  final DateTime end;

  EventEditorResult({required this.title, required this.start, required this.end});
}

Future<EventEditorResult?> showEventEditorBottomSheet({
  required BuildContext context,
  String? initialTitle,
  DateTime? initialStart,
  DateTime? initialEnd,
}) {
  final titleController = TextEditingController(text: initialTitle ?? '');
  DateTime start = initialStart ?? DateTime.now();
  DateTime end = initialEnd ?? DateTime.now().add(const Duration(days: 1));

  return showModalBottomSheet<EventEditorResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 16,
          left: 16,
          right: 16,
        ),
        child: Wrap(
          children: [
            const Text("일정 제목", style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(hintText: '예: 프로젝트 회의'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text("시작일: "),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: start,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      start = picked;
                    }
                  },
                  child: Text("${start.year}-${start.month}-${start.day}"),
                ),
              ],
            ),
            Row(
              children: [
                const Text("종료일: "),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: end,
                      firstDate: start,
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      end = picked;
                    }
                  },
                  child: Text("${end.year}-${end.month}-${end.day}"),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, null); // 취소
                  },
                  child: const Text("취소"),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) return;
                    Navigator.pop(
                      context,
                      EventEditorResult(
                        title: titleController.text.trim(),
                        start: start,
                        end: end,
                      ),
                    );
                  },
                  child: const Text("저장"),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
}