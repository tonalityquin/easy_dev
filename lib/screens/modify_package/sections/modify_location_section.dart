import 'package:flutter/material.dart';
import '../widgets/modify_location_field.dart';

class ModifyLocationSection extends StatelessWidget {
  final TextEditingController locationController;

  const ModifyLocationSection({
    super.key,
    required this.locationController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
      children: [
        const Text(
          '주차 구역',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8.0),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ModifyLocationField(
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
