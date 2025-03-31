import 'package:flutter/material.dart';

class ConfirmCancelFeeDialog extends StatefulWidget {
  const ConfirmCancelFeeDialog({super.key});

  @override
  State<ConfirmCancelFeeDialog> createState() => _ConfirmCancelFeeDialogState();
}

class _ConfirmCancelFeeDialogState extends State<ConfirmCancelFeeDialog> {
  bool isEnabled = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          isEnabled = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        '정산 취소 확인',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        textAlign: TextAlign.center,
      ),
      content: const Text(
        '정산을 취소하시겠습니까?\n\n취소 후에는 요금이 변경될 수 있습니다.',
        style: TextStyle(fontSize: 15),
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
          child: const Text('아니오'),
        ),
        TextButton(
          onPressed: isEnabled ? () => Navigator.of(context).pop(true) : null,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(isEnabled ? '예, 취소합니다' : '5초 뒤, 활성화됩니다'),
        ),
      ],
    );
  }
}
