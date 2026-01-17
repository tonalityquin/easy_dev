import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/plate_limit/status_mapping_helper.dart';

class DoubleModifyStatusOnTapSection extends StatefulWidget {
  final List<String>? initialSelectedStatuses;

  final String? initialCategory;

  final ValueChanged<List<String>>? onSelectionChanged;

  const DoubleModifyStatusOnTapSection({
    super.key,
    this.initialSelectedStatuses,
    this.initialCategory,
    this.onSelectionChanged,
  });

  @override
  State<DoubleModifyStatusOnTapSection> createState() => _DoubleModifyStatusOnTapSectionState();
}

class _DoubleModifyStatusOnTapSectionState extends State<DoubleModifyStatusOnTapSection> {
  String? selectedCategory;
  Set<int> selectedIndexes = {};

  @override
  void initState() {
    super.initState();
    _loadInitialCategoryAndStatuses();
  }

  Future<void> _loadInitialCategoryAndStatuses() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCategory = prefs.getString('selected_category');

    setState(() {
      selectedCategory = savedCategory?.isNotEmpty == true
          ? savedCategory
          : (widget.initialCategory?.isNotEmpty == true ? widget.initialCategory : '공통');
    });

    if (selectedCategory != null && widget.initialSelectedStatuses != null) {
      final currentStatuses = StatusMappingHelper.getStatuses(selectedCategory!);
      selectedIndexes =
          widget.initialSelectedStatuses!.map((name) => currentStatuses.indexOf(name)).where((i) => i != -1).toSet();
    }

    _notifySelection();
  }

  Future<void> _saveSelectedCategory(String? category) async {
    final prefs = await SharedPreferences.getInstance();
    if (category != null && category.isNotEmpty) {
      await prefs.setString('selected_category', category);
    } else {
      await prefs.remove('selected_category');
    }
  }

  void _notifySelection() {
    if (selectedCategory == null || widget.onSelectionChanged == null) return;

    final currentStatuses = StatusMappingHelper.getStatuses(selectedCategory!);
    final selectedNames =
        selectedIndexes.where((i) => i < currentStatuses.length).map((i) => currentStatuses[i]).toList();
    widget.onSelectionChanged!(selectedNames);
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
          onChanged: (value) async {
            setState(() {
              selectedCategory = value;
              selectedIndexes.clear();
            });
            await _saveSelectedCategory(value);
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
                  _notifySelection();
                },
                selectedColor: theme.primaryColor.withOpacity(0.2),
                backgroundColor: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: selected ? theme.primaryColor : Colors.grey.shade300,
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
