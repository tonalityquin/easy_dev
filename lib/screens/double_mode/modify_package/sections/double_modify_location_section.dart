import 'package:flutter/material.dart';
import '../widgets/double_modify_location_field.dart';

class DoubleModifyLocationSection extends StatelessWidget {
  final TextEditingController locationController;

  const DoubleModifyLocationSection({
    super.key,
    required this.locationController,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '주차 구역',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8.0),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DoubleModifyLocationField(
                controller: locationController,
                widthFactor: 0.7,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
