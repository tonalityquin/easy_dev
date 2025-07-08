import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/status_mapping_helper.dart';

class InputStatusOnTapSection extends StatefulWidget {
  /// 부모에게 선택된 상태 목록을 전달하는 콜백
  final ValueChanged<List<String>>? onSelectionChanged;

  /// 초기 선택된 상태 이름들
  final List<String>? initialSelectedStatuses;

  /// 초기 업종
  final String? initialCategory;

  const InputStatusOnTapSection({
    super.key,
    this.onSelectionChanged,
    this.initialSelectedStatuses,
    this.initialCategory,
  });

  @override
  State<InputStatusOnTapSection> createState() =>
      _InputStatusOnTapSectionState();
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

    // SharedPreferences > initialCategory > 기본값 '공통'
    setState(() {
      selectedCategory = saved?.isNotEmpty == true
          ? saved
          : (widget.initialCategory?.isNotEmpty == true
          ? widget.initialCategory
          : '공통');
    });

    _restoreInitialStatuses();
  }

  void _restoreInitialStatuses() {
    if (selectedCategory == null || widget.initialSelectedStatuses == null) return;

    final currentStatuses = StatusMappingHelper.getStatuses(selectedCategory);
    final restoredIndexes = <int>{};

    for (int i = 0; i < currentStatuses.length; i++) {
      if (widget.initialSelectedStatuses!.contains(currentStatuses[i])) {
        restoredIndexes.add(i);
      }
    }

    setState(() {
      selectedIndexes = restoredIndexes;
    });

    widget.onSelectionChanged?.call(
      selectedIndexes.map((i) => currentStatuses[i]).toList(),
    );
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
    final currentStatuses = StatusMappingHelper.getStatuses(selectedCategory);

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

            _restoreInitialStatuses();
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
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? theme.primaryColor : Colors.black87,
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
