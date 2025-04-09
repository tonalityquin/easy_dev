import 'package:flutter/material.dart';

class AdjustmentContainer extends StatelessWidget {
  final String countType;
  final String basicStandard;
  final String basicAmount;
  final String addStandard;
  final String addAmount;
  final bool isSelected;
  final VoidCallback onTap;

  const AdjustmentContainer({
    super.key,
    required this.countType,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
    required this.isSelected,
    required this.onTap,
  });

  Widget _buildTextRow(String label, String value) {
    return Text('$label: $value');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextRow('CountType', countType),
            _buildTextRow('BasicStandard', basicStandard),
            _buildTextRow('BasicAmount', basicAmount),
            _buildTextRow('AddStandard', addStandard),
            _buildTextRow('AddAmount', addAmount),
          ],
        ),
      ),
    );
  }
}
