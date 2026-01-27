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
    final cs = Theme.of(context).colorScheme;
    final currentStatuses = StatusMappingHelper.getStatuses(selectedCategory);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: selectedCategory,
          hint: const Text('업종 선택'),
          decoration: InputDecoration(
            labelText: '업종',
            filled: true,
            fillColor: cs.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 1.6),
            ),
          ),
          dropdownColor: cs.surface,
          items: StatusMappingHelper.categories.map((category) {
            return DropdownMenuItem(
              value: category,
              child: Text(category, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
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
        Text(
          '차량 상태',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),

        if (currentStatuses.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
            ),
            child: Text(
              '업종을 선택하세요.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(currentStatuses.length, (index) {
              final selected = selectedIndexes.contains(index);

              final fg = selected ? cs.primary : cs.onSurface;
              final bg = selected ? cs.primary.withOpacity(0.12) : cs.surfaceContainerLow;
              final border = selected ? cs.primary.withOpacity(0.55) : cs.outlineVariant.withOpacity(0.85);

              return ChoiceChip(
                label: Text(
                  currentStatuses[index],
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: fg,
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
                selectedColor: bg,
                backgroundColor: bg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              );
            }),
          ),

        const SizedBox(height: 16),

        if (selectedCategory != null && selectedIndexes.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '선택된 상태:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: cs.onSurface),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: selectedIndexes
                    .map(
                      (i) => Chip(
                    label: Text(currentStatuses[i], style: TextStyle(color: cs.onSurface)),
                    backgroundColor: cs.primary.withOpacity(0.10),
                    side: BorderSide(color: cs.primary.withOpacity(0.35)),
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
