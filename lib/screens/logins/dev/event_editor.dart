import 'package:flutter/material.dart';

class ChecklistItem {
  String text;
  bool checked;

  ChecklistItem({required this.text, this.checked = false});
}

class EventEditorResult {
  final String title;
  final DateTime start;
  final DateTime end;
  final List<ChecklistItem> checklist;
  final String description;
  final bool deleted; // ✅ 추가

  EventEditorResult({
    required this.title,
    required this.start,
    required this.end,
    required this.checklist,
    required this.description,
    this.deleted = false, // 기본값 false
  });
}


Future<EventEditorResult?> showEventEditorBottomSheet({
  required BuildContext context,
  String? initialTitle,
  DateTime? initialStart,
  DateTime? initialEnd,
  List<ChecklistItem>? initialChecklist,
}) {
  final titleController = TextEditingController(text: initialTitle ?? '');
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _saveFocus = FocusNode();

  DateTime start = initialStart ?? DateTime.now();
  DateTime end = initialEnd ?? DateTime.now().add(const Duration(days: 1));

  final List<ChecklistItem> checklist = initialChecklist != null
      ? initialChecklist.map((item) => ChecklistItem(text: item.text, checked: item.checked)).toList()
      : [];

  final List<TextEditingController> controllers =
  checklist.map((item) => TextEditingController(text: item.text)).toList();

  void addChecklistItem() {
    checklist.add(ChecklistItem(text: ""));
    controllers.add(TextEditingController());
  }

  String generateDescription(List<ChecklistItem> list) {
    final total = list.length;
    final done = list.where((item) => item.checked).length;
    final progress = total > 0 ? ((done / total) * 100).round() : 0;
    final checklistText = list.map((item) => '- [${item.checked ? "x" : " "}] ${item.text.trim()}').join('\n');
    return 'progress:$progress\n$checklistText';
  }


  return showModalBottomSheet<EventEditorResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 16,
            left: 16,
            right: 16,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("할 일 제목", style: TextStyle(fontWeight: FontWeight.bold)),
                    TextField(
                      focusNode: _titleFocus,
                      controller: titleController,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      decoration: const InputDecoration(hintText: '예: 프로젝트 기획서 작성'),
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
                              setState(() => start = picked);
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
                              initialDate: end.isBefore(start) ? start : end,
                              firstDate: start,
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setState(() => end = picked);
                              FocusScope.of(context).requestFocus(_saveFocus);
                            }
                          },
                          child: Text("${end.year}-${end.month}-${end.day}"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("체크리스트", style: TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            setState(() {
                              addChecklistItem();
                            });
                          },
                        ),
                      ],
                    ),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: checklist.length,
                      itemBuilder: (context, index) {
                        final item = checklist[index];
                        final controller = controllers[index];
                        return Row(
                          children: [
                            Checkbox(
                              value: item.checked,
                              onChanged: (value) {
                                setState(() {
                                  item.checked = value ?? false;
                                });
                              },
                            ),
                            Expanded(
                              child: TextField(
                                controller: controller,
                                onChanged: (value) => item.text = value,
                                decoration: const InputDecoration(hintText: '체크 항목 입력'),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  checklist.removeAt(index);
                                  controllers.removeAt(index);
                                });
                              },
                            )
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, null),
                          child: const Text("취소"),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(
                              context,
                              EventEditorResult(
                                title: '',
                                start: start,
                                end: end,
                                checklist: [],
                                description: '',
                                deleted: true, // ✅ 삭제 처리용
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text("삭제"),
                        ),
                        ElevatedButton(
                          focusNode: _saveFocus,
                          onPressed: () {
                            if (titleController.text.trim().isEmpty) return;

                            for (int i = 0; i < checklist.length; i++) {
                              checklist[i].text = controllers[i].text.trim();
                            }

                            final description = generateDescription(checklist);

                            Navigator.pop(
                              context,
                              EventEditorResult(
                                title: titleController.text.trim(),
                                start: start,
                                end: end,
                                checklist: checklist,
                                description: description,
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
          ),
        ),
      );
    },
  );
}
