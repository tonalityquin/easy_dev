import 'package:flutter/material.dart';

class ModifyStatusOnTapSection extends StatelessWidget {
  final List<String> statuses;
  final List<bool> isSelected;
  final ValueChanged<int> onToggle;

  const ModifyStatusOnTapSection({
    super.key,
    required this.statuses,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('차량 상태', style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8.0),
        statuses.isEmpty
            ? const Text('등록된 차량 상태가 없습니다.')
            : Wrap(
          spacing: 8.0,
          children: List.generate(statuses.length, (index) {
            return ChoiceChip(
              label: Text(statuses[index]),
              selected: isSelected[index],
              onSelected: (_) => onToggle(index),
            );
          }),
        ),
      ],
    );
  }
}
