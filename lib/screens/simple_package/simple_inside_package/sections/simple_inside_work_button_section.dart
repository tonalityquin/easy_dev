// lib/screens/simple_package/simple_inside_package/sections/simple_inside_work_button_section.dart
import 'package:flutter/material.dart';

class SimpleInsideWorkButtonSection extends StatefulWidget {
  const SimpleInsideWorkButtonSection({
    super.key,
  });

  @override
  State<SimpleInsideWorkButtonSection> createState() => _SimpleInsideWorkButtonSectionState();
}

class _SimpleInsideWorkButtonSectionState extends State<SimpleInsideWorkButtonSection> {
  /// true  : 출근 중 상태
  /// false : 아직 출근 전 상태
  bool _isWorking = false;

  void _toggleWorkingState() {
    setState(() {
      _isWorking = !_isWorking;
    });

    // TODO: 여기에서 실제 출근 처리 / 출근 취소 로직을 연결하면 됩니다.
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Icon(
        _isWorking ? Icons.pause_circle_filled : Icons.access_time,
      ),
      label: Text(
        _isWorking ? '출근 중..' : '출근하기',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: const BorderSide(color: Colors.grey, width: 1.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: _toggleWorkingState,
    );
  }
}
