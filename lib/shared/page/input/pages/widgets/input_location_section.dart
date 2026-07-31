import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../application/input_location_field.dart';
import '../common_input_ui.dart';

class InputLocationSection extends StatelessWidget {
  final TextEditingController locationController;

  const InputLocationSection({
    super.key,
    required this.locationController,
  });

  @override
  Widget build(BuildContext context) {
    return CommonAnimatedReveal(
      offset: const Offset(0, .025),
      child: CommonInputSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CommonInputSectionTitle(
              icon: Icons.local_parking_rounded,
              title: '주차 구역',
              subtitle: '차량이 배치될 구역과 슬롯을 선택합니다.',
            ),
            const SizedBox(height: 14),
            Center(
              child: InputLocationField(
                controller: locationController,
                widthFactor: .88,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
