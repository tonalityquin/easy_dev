import 'package:flutter/material.dart';

typedef AddTaskCallback = void Function(Map<String, dynamic> task);

void showAddTaskBottomSheet({
  required BuildContext context,
  required int totalDays,
  required AddTaskCallback onTaskAdd,
}) {
  final nameController = TextEditingController();
  final descController = TextEditingController();
  RangeValues selectedRange = const RangeValues(1, 3);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '작업 추가',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '작업 이름'),
                  ),
                  const SizedBox(height: 12),
                  Text("기간: ${selectedRange.start.toInt()}일 ~ ${selectedRange.end.toInt()}일"),
                  RangeSlider(
                    values: selectedRange,
                    min: 1,
                    max: totalDays.toDouble(),
                    divisions: totalDays - 1,
                    labels: RangeLabels(
                      "${selectedRange.start.toInt()}일",
                      "${selectedRange.end.toInt()}일",
                    ),
                    onChanged: (range) {
                      setModalState(() {
                        selectedRange = range;
                      });
                    },
                  ),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: '설명'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        child: const Text('취소'),
                        onPressed: () => Navigator.pop(context),
                      ),
                      ElevatedButton(
                        child: const Text('추가'),
                        onPressed: () {
                          final name = nameController.text.trim();
                          final desc = descController.text.trim();
                          final start = selectedRange.start.toInt();
                          final end = selectedRange.end.toInt();

                          if (name.isNotEmpty && start > 0 && end >= start && end <= totalDays) {
                            final task = {
                              'name': name,
                              'start': start,
                              'end': end,
                              'description': desc,
                            };

                            onTaskAdd(task); // 콜백으로 전달
                            Navigator.pop(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('입력값을 확인하세요.')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
