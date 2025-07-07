import 'package:flutter/material.dart';

class HeaderWidget extends StatelessWidget {
  const HeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 96),
        SizedBox(
          height: 120,
          child: Image.asset('assets/images/belivus_logo.PNG'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
