import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/status_mapping_helper.dart';

class InputStatusOnTapSection extends StatefulWidget {
  /// 부모에 현재 선택된 상태 리스트를 알려주고 싶으면 이 콜백 사용
  final ValueChanged<List<String>>? onSelectionChanged;

  const InputStatusOnTapSection({
    super.key,
    this.onSelectionChanged,
  });

  @override
  State<InputStatusOnTapSection> createState() => _InputStatusOnTapSectionState();
}

class _InputStatusOnTapSectionState extends State<InputStatusOnTapSection> {
  String? selectedCategory;
  Set<int> selectedIndexes = {};

  @override
  void initState() {
    super.initState();
    _loadSavedCategory();
  }

  Future<void> _loadSavedCategory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('selected_category');
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        selectedCategory = saved;
      });
    }
  }

  Future<void> _saveCategory(String? category) async {
    final prefs = await SharedPreferences.getInstance();
    if (category != null) {
      await prefs.setString('selected_category', category);
    } else {
      await prefs.remove('selected_category');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final List<String> currentStatuses =
    StatusMappingHelper.getStatuses(selectedCategory);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: selectedCategory,
          hint: const Text('업종 선택'),
          decoration: const InputDecoration(
            labelText: '업종',
            border: OutlineInputBorder(),
          ),
          items: StatusMappingHelper.categories.map((category) {
            return DropdownMenuItem(
              value: category,
              child: Text(category),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              selectedCategory = value;
              selectedIndexes.clear();
            });
            _saveCategory(value);
            // 업종 바뀌면 선택 리스트 초기화
            widget.onSelectionChanged?.call([]);
          },
        ),
        const SizedBox(height: 16),
        const Text(
          '차량 상태',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (currentStatuses.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '업종을 선택하세요.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(currentStatuses.length, (index) {
              final selected = selectedIndexes.contains(index);
              return ChoiceChip(
                label: Text(
                  currentStatuses[index],
                  style: TextStyle(
                    fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? theme.primaryColor
                        : Colors.black87,
                  ),
                ),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    if (selected) {
                      selectedIndexes.remove(index);
                    } else {
                      selectedIndexes.add(index);
                    }
                  });
                  // 상태가 바뀔 때마다 선택된 상태 목록 부모에 전달
                  widget.onSelectionChanged?.call(
                    selectedIndexes.map((i) => currentStatuses[i]).toList(),
                  );
                },
                selectedColor: theme.primaryColor.withOpacity(0.2),
                backgroundColor: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: selected
                        ? theme.primaryColor
                        : Colors.grey.shade300,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              );
            }),
          ),
        const SizedBox(height: 16),
        if (selectedCategory != null && selectedIndexes.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '선택된 상태:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: selectedIndexes
                    .map(
                      (i) => Chip(
                    label: Text(currentStatuses[i]),
                    backgroundColor: theme.primaryColor.withOpacity(0.1),
                  ),
                )
                    .toList(),
              ),
            ],
          ),
      ],
    );
  }
}
