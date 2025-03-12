import 'package:flutter/material.dart';

class DepartureCompletedConfirmDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const DepartureCompletedConfirmDialog({super.key, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('출차 완료 확인'),
      content: const Text('정말로 출차 완료 처리를 하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onConfirm();
          },
          child: const Text('확인', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}
