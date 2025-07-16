// time_edit_bottom_sheet.dart
import 'package:flutter/material.dart';

typedef OnTimeSaved = void Function(String inTime, String outTime);

void showTimeEditBottomSheet({
  required BuildContext context,
  required DateTime day,
  required String initialInTime,
  required String initialOutTime,
  required OnTimeSaved onSaved,
}) {
  final inTimeParts = initialInTime.split(':');
  final outTimeParts = initialOutTime.split(':');

  final inHourController = TextEditingController(text: inTimeParts[0]);
  final inMinController = TextEditingController(text: inTimeParts[1]);

  final outHourController = TextEditingController(text: outTimeParts[0]);
  final outMinController = TextEditingController(text: outTimeParts[1]);

  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            _TimeInputRow('출근 시간', inHourController, inMinController),
            const SizedBox(height: 12),
            _TimeInputRow('퇴근 시간', outHourController, outMinController),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('저장'),
              onPressed: () {
                final inTime = '${inHourController.text.padLeft(2, '0')}:${inMinController.text.padLeft(2, '0')}';
                final outTime = '${outHourController.text.padLeft(2, '0')}:${outMinController.text.padLeft(2, '0')}';

                onSaved(inTime, outTime);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(45)),
            ),
          ],
        ),
      );
    },
  );
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
