import 'package:flutter/material.dart';

class DepartureRequestStatusDialog extends StatelessWidget {
  final VoidCallback onRequestEntry;
  final VoidCallback onCompleteDeparture;
  final VoidCallback onDelete;

  const DepartureRequestStatusDialog({
    super.key,
    required this.onRequestEntry,
    required this.onCompleteDeparture,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("상태 수정"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text("입차 요청"),
            onTap: () {
              Navigator.pop(context);
              onRequestEntry();
            },
          ),
          ListTile(
            title: const Text("출차 완료"),
            onTap: () {
              Navigator.pop(context);
              onCompleteDeparture();
            },
          ),
          ListTile(
            title: const Text("삭제"),
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}
