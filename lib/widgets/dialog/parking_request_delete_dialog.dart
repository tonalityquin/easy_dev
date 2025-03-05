import 'package:flutter/material.dart';

class ParkingRequestDeleteDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const ParkingRequestDeleteDialog({Key? key, required this.onConfirm}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('확인'),
      content: const Text('정말 삭제하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            onConfirm();
            Navigator.of(context).pop();
          },
          child: const Text('확인'),
        ),
      ],
    );
  }
}
