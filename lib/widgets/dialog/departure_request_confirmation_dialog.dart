import 'package:flutter/material.dart';

class DepartureRequestConfirmDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const DepartureRequestConfirmDialog({super.key, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('출차 요청 확인'),
      content: const Text('정말로 출차 요청을 진행하시겠습니까?'),
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
