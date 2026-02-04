import 'package:flutter/material.dart';

class SingleInsideHeaderWidgetSection extends StatelessWidget {
  const SingleInsideHeaderWidgetSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        SizedBox(
          height: 240,
          child: Image.asset('assets/images/pelican.png'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
