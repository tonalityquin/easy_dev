import 'package:flutter/material.dart';

class StatusMappingHelper extends StatelessWidget {
  const StatusMappingHelper({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '📌 현재는 Plate limit 기능이 비활성화되어 있습니다.',
          style: TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
