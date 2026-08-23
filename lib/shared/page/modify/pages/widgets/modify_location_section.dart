import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../application/modify_location_field.dart';

class ModifyLocationSection extends StatelessWidget {
  const ModifyLocationSection({
    super.key,
    required this.locationController,
  });

  final TextEditingController locationController;

  @override
  Widget build(BuildContext context) {
    return CommonSideDockSection(
      order: 1,
      title: '주차 구역',
      child: Center(
        child: ModifyLocationField(
          controller: locationController,
          widthFactor: .96,
        ),
      ),
    );
  }
}
