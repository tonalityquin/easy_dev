import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/plate_limit/status_mapping_helper.dart';

class MinorModifyStatusOnTapSection extends StatefulWidget {
  final List<String>? initialSelectedStatuses;
  final String? initialCategory;
  final ValueChanged<List<String>>? onSelectionChanged;

  const MinorModifyStatusOnTapSection({
    super.key,
    this.initialSelectedStatuses,
    this.initialCategory,
    this.onSelectionChanged,
  });

  @override
  State<MinorModifyStatusOnTapSection> createState() =>
      _MinorModifyStatusOnTapSectionState();
}

class _MinorModifyStatusOnTapSectionState
    extends State<MinorModifyStatusOnTapSection> {
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

    final resolvedCategory = (savedCategory?.trim().isNotEmpty ?? false)
        ? savedCategory!.trim()
        : ((widget.initialCategory?.trim().isNotEmpty ?? false)
        ? widget.initialCategory!.trim()
        : '공통');

    final currentStatuses = StatusMappingHelper.getStatuses(resolvedCategory);

    final initial = widget.initialSelectedStatuses ?? const <String>[];
    final initIndexes = <int>{};
    for (final name in initial) {
      final idx = currentStatuses.indexOf(name);
      if (idx >= 0) initIndexes.add(idx);
    }

    if (!mounted) return;
    setState(() {
      selectedCategory = resolvedCategory;
      selectedIndexes = initIndexes;
    });

    _notifySelection();
  }

  Future<void> _saveSelectedCategory(String? category) async {
    final prefs = await SharedPreferences.getInstance();
    final c = category?.trim() ?? '';
    if (c.isNotEmpty) {
      await prefs.setString('selected_category', c);
    } else {
      await prefs.remove('selected_category');
    }
  }

  void _notifySelection() {
    final c = selectedCategory;
    final cb = widget.onSelectionChanged;
    if (c == null || cb == null) return;

    final statuses = StatusMappingHelper.getStatuses(c);
    final names = selectedIndexes
        .where((i) => i >= 0 && i < statuses.length)
        .map((i) => statuses[i])
        .toList();

    cb(names);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final c = selectedCategory ?? '공통';
    final currentStatuses = StatusMappingHelper.getStatuses(c);

    // ✅ out-of-range 방지: 목록 길이가 변했을 때 selectedIndexes 정리
    final sanitized = selectedIndexes.where((i) => i >= 0 && i < currentStatuses.length).toSet();
    if (sanitized.length != selectedIndexes.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => selectedIndexes = sanitized);
        _notifySelection();
      });
    }

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
            final newCat = (value ?? '').trim();
            if (!mounted) return;

            setState(() {
              selectedCategory = newCat.isEmpty ? '공통' : newCat;
              selectedIndexes.clear();
            });

            await _saveSelectedCategory(selectedCategory);
            _notifySelection(); // ✅ 선택 초기화 후 콜백(빈 목록)
          },
        ),
        const SizedBox(height: 16),
        Text(
          '차량 상태',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
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
              style: TextStyle(color: Colors.black54, fontSize: 14),
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
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    color: selected ? theme.colorScheme.primary : Colors.black87,
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
                selectedColor: theme.colorScheme.primary.withOpacity(0.15),
                backgroundColor: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: selected ? theme.colorScheme.primary : Colors.grey.shade300,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              );
            }),
          ),
        const SizedBox(height: 16),
        if (selectedIndexes.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '선택된 상태:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: selectedIndexes
                    .where((i) => i >= 0 && i < currentStatuses.length)
                    .map(
                      (i) => Chip(
                    label: Text(currentStatuses[i]),
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.10),
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
