import 'package:flutter/material.dart';

class CustomStatusSection extends StatelessWidget {
  final String customStatus;
  final VoidCallback onDelete;

  const CustomStatusSection({
    super.key,
    required this.customStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('자동 불러온 상태 메모', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: TextEditingController(text: customStatus),
                readOnly: true,
                maxLines: null,
                style: const TextStyle(color: Colors.grey),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.clear, color: Colors.red),
              tooltip: '자동 메모 지우기',
            ),
          ],
        ),
      ],
    );
  }
}
