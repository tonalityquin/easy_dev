import 'package:flutter/material.dart';

class EventEditorResult {
  final String title;
  final String description;
  final bool done;

  EventEditorResult({
    required this.title,
    required this.description,
    required this.done,
  });
}

Future<EventEditorResult?> showEventEditorBottomSheet({
  required BuildContext context,
  String initialTitle = '',
  String initialDescription = '',
  bool initialDone = false,
  bool isEdit = false,
  VoidCallback? onDelete,
}) {
  final titleController = TextEditingController(text: initialTitle);
  final descriptionController = TextEditingController(text: initialDescription);
  final formKey = GlobalKey<FormState>();
  bool done = initialDone;

  return showModalBottomSheet<EventEditorResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 24,
        ),
        child: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isEdit ? '일정 수정' : '일정 추가',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: '제목',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                      value == null || value.trim().isEmpty ? '제목을 입력해주세요' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: '설명',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      maxLines: null,
                      minLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Switch(
                          value: done,
                          onChanged: (value) => setState(() => done = value),
                        ),
                        const Text('완료된 일정입니다.'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isEdit && onDelete != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            label: const Text('일정 삭제', style: TextStyle(color: Colors.red)),
                            onPressed: () {
                              Navigator.pop(context);
                              onDelete();
                            },
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.close),
                                label: const Text('취소'),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: Icon(isEdit ? Icons.edit : Icons.add),
                                label: Text(isEdit ? '수정 완료' : '일정 추가'),
                                onPressed: () {
                                  if (formKey.currentState!.validate()) {
                                    Navigator.pop(
                                      context,
                                      EventEditorResult(
                                        title: titleController.text.trim(),
                                        description: descriptionController.text.trim(),
                                        done: done,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}
