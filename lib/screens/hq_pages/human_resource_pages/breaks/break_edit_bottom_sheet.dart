import 'package:flutter/material.dart';

typedef TimeSaveCallback = void Function(String hhmm);

class BreakEditBottomSheet extends StatelessWidget {
  final DateTime date;
  final String initialTime;
  final TimeSaveCallback onSave;

  const BreakEditBottomSheet({
    super.key,
    required this.date,
    required this.initialTime,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final parts = initialTime.split(':');
    final hourController = TextEditingController(text: parts[0]);
    final minController = TextEditingController(text: parts[1]);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          /// 날짜
          Text(
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),

          _TimeInputRow('휴게 시간', hourController, minController),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            icon: const Icon(Icons.save, size: 20),
            label: const Text(
              '저장',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            onPressed: () {
              final time = '${hourController.text.padLeft(2, '0')}:${minController.text.padLeft(2, '0')}';
              onSave(time);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _TimeInputRow extends StatelessWidget {
  final String label;
  final TextEditingController hourCtrl;
  final TextEditingController minCtrl;

  const _TimeInputRow(this.label, this.hourCtrl, this.minCtrl);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Row(
          children: [
            Flexible(
              child: TextField(
                controller: hourCtrl,
                keyboardType: TextInputType.number,
                maxLength: 2,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: 'HH',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(':', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                maxLength: 2,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: 'MM',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
