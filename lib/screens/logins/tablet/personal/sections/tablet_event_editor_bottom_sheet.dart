import 'package:flutter/material.dart';

// 체크리스트 항목 데이터 클래스
class ChecklistItem {
  String text;
  bool checked;

  ChecklistItem({required this.text, this.checked = false});
}

// 바텀시트 종료 시 전달할 이벤트 결과 데이터 클래스
class EventEditorResult {
  final String title;
  final DateTime start;
  final DateTime end;
  final List<ChecklistItem> checklist;
  final String description;
  final bool deleted;
  final String? colorId;

  EventEditorResult({
    required this.title,
    required this.start,
    required this.end,
    required this.checklist,
    required this.description,
    this.deleted = false,
    this.colorId,
  });
}

// 이벤트 추가/수정 바텀시트를 표시하고 결과를 반환하는 함수
Future<EventEditorResult?> showTabletEventEditorBottomSheet({
  required BuildContext context,
  String? initialTitle,
  DateTime? initialStart,
  DateTime? initialEnd,
  List<ChecklistItem>? initialChecklist,
  String? initialColorId,
}) {
  final titleController = TextEditingController(text: initialTitle ?? '');
  final FocusNode titleFocus = FocusNode();
  final FocusNode saveFocus = FocusNode();

  DateTime start = initialStart ?? DateTime.now();
  DateTime end = initialEnd ?? DateTime.now().add(const Duration(days: 1));

  // 체크리스트 복사 및 개별 컨트롤러 생성
  final List<ChecklistItem> checklist = initialChecklist != null
      ? initialChecklist.map((item) => ChecklistItem(text: item.text, checked: item.checked)).toList()
      : [];
  final List<TextEditingController> controllers =
      checklist.map((item) => TextEditingController(text: item.text)).toList();

  // 색상 선택 초기화 및 색상 맵 정의
  String? selectedColorId = initialColorId ?? "1";
  final Map<String, Color> colorOptions = {
    "1": Colors.blue,
    "2": Colors.green,
    "3": Colors.purple,
    "4": Colors.red,
    "5": Colors.yellow,
    "6": Colors.orange,
    "7": Colors.teal,
    "8": Colors.grey,
    "9": Colors.brown,
    "10": Colors.cyan,
    "11": Colors.indigo,
  };

  // 체크리스트 항목 추가 함수
  void addChecklistItem() {
    checklist.add(ChecklistItem(text: ""));
    controllers.add(TextEditingController());
  }

  // 체크리스트 상태 기반 설명 생성 (진행률 포함)
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
                    // 제목 입력 필드
                    const Text("할 일 제목", style: TextStyle(fontWeight: FontWeight.bold)),
                    TextField(
                      focusNode: titleFocus,
                      controller: titleController,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      decoration: const InputDecoration(hintText: '예: 프로젝트 기획서 작성'),
                    ),
                    const SizedBox(height: 16),

                    // 시작일 선택
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

                    // 종료일 선택
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
                              FocusScope.of(context).requestFocus(saveFocus);
                            }
                          },
                          child: Text("${end.year}-${end.month}-${end.day}"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 색상 선택 UI
                    const Text("이벤트 색상", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: colorOptions.entries.map((entry) {
                        final isSelected = selectedColorId == entry.key;
                        return GestureDetector(
                          onTap: () => setState(() => selectedColorId = entry.key),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: entry.value,
                              shape: BoxShape.circle,
                              border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    // 체크리스트 제목 + 추가 버튼
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

                    // 체크리스트 항목 목록
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: checklist.length,
                      itemBuilder: (context, index) {
                        final item = checklist[index];
                        final controller = controllers[index];
                        return Row(
                          children: [
                            // 체크 여부
                            Checkbox(
                              value: item.checked,
                              onChanged: (value) {
                                setState(() {
                                  item.checked = value ?? false;
                                });
                              },
                            ),
                            // 텍스트 입력
                            Expanded(
                              child: TextField(
                                controller: controller,
                                onChanged: (value) => item.text = value,
                                decoration: const InputDecoration(hintText: '체크 항목 입력'),
                              ),
                            ),
                            // 삭제 버튼
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

                    // 하단 버튼들: 취소, 삭제, 저장
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
                                deleted: true,
                                colorId: selectedColorId,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text("삭제"),
                        ),
                        ElevatedButton(
                          focusNode: saveFocus,
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
                                colorId: selectedColorId,
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
