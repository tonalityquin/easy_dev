import 'package:flutter/material.dart';

import '../../utils/common_brand_tinted_logo.dart';

class CommonCommuteInHeaderWidget extends StatelessWidget {
  const CommonCommuteInHeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 24),
        SizedBox(
          height: 240,
          child: CommonBrandTintedLogo(
            assetPath: 'assets/images/ParkinWorkin_logo.png',
            height: 240,
          ),
        ),
        SizedBox(height: 12),
      ],
    );
  }
}
