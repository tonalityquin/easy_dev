import 'package:flutter/material.dart';

class InputStatusOnTapSection extends StatelessWidget {
  final List<String> statuses;
  final List<bool> isSelected;
  final ValueChanged<int> onToggle;

  const InputStatusOnTapSection({
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
        const Text(
          '차량 상태',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8.0),
        if (statuses.isEmpty)
          const Text(
            '등록된 차량 상태가 없습니다.',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 14.0,
            ),
          )
        else
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: List.generate(statuses.length, (index) {
              return ChoiceChip(
                label: Text(statuses[index]),
                selected: isSelected[index],
                onSelected: (_) => onToggle(index),
                selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
                labelStyle: TextStyle(
                  color: isSelected[index] ? Theme.of(context).primaryColor : Colors.black87,
                  fontWeight: isSelected[index] ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }),
          ),
      ],
    );
  }
}
