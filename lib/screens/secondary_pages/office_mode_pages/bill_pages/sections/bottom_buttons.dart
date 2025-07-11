import 'package:flutter/material.dart';

class BottomButtons extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const BottomButtons({super.key, required this.onCancel, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            child: const Text('취소'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: onSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('저장'),
          ),
        ),
      ],
    );
  }
}
