import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../application/modify_location_field.dart';
import '../common_modify_ui.dart';

class ModifyLocationSection extends StatelessWidget {
  const ModifyLocationSection({
    super.key,
    required this.locationController,
  });

  final TextEditingController locationController;

  @override
  Widget build(BuildContext context) {
    return CommonAnimatedReveal(
      offset: const Offset(0, .025),
      child: CommonModifySectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CommonModifySectionTitle(
              icon: Icons.local_parking_rounded,
              title: '주차 구역',
              subtitle: '차량의 현재 구역과 슬롯을 확인하거나 변경합니다.',
            ),
            const SizedBox(height: 14),
            Center(
              child: ModifyLocationField(
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
