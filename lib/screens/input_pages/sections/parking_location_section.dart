// 파일 위치: input_pages/sections/parking_location_section.dart

import 'package:flutter/material.dart';
import '../../../widgets/input_field/location_field.dart';

class ParkingLocationSection extends StatelessWidget {
  final TextEditingController locationController;

  const ParkingLocationSection({
    super.key,
    required this.locationController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('주차 구역', style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8.0),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LocationField(
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
