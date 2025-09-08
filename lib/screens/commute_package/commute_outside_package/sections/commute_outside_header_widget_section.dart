import 'package:flutter/material.dart';

class CommuteOutsideHeaderWidgetSection extends StatelessWidget {
  const CommuteOutsideHeaderWidgetSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        SizedBox(
          height: 240,
          child: Image.asset('assets/images/easyvalet_logo_car.png'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
