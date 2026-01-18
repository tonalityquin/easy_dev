import 'package:flutter/material.dart';
import '../utils/minor_input_location_field.dart';

class MinorInputLocationSection extends StatelessWidget {
  final TextEditingController locationController;

  const MinorInputLocationSection({
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
              MinorInputLocationField(
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
