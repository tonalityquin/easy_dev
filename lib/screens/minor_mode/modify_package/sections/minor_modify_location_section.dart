import 'package:flutter/material.dart';
import '../widgets/minor_modify_location_field.dart';

class MinorModifyLocationSection extends StatelessWidget {
  final TextEditingController locationController;

  const MinorModifyLocationSection({
    super.key,
    required this.locationController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '주차 구역',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: MinorModifyLocationField(
            controller: locationController,
            widthFactor: 0.7,
          ),
        ),
      ],
    );
  }
}
