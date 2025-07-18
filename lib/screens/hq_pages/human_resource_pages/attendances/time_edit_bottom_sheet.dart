import 'package:flutter/material.dart';

typedef OnTimeSaved = void Function(String inTime, String outTime);

class TimeEditBottomSheet extends StatelessWidget {
  final DateTime date;
  final String initialInTime;
  final String initialOutTime;
  final OnTimeSaved onSave;

  const TimeEditBottomSheet({
    super.key,
    required this.date,
    required this.initialInTime,
    required this.initialOutTime,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final inTimeParts = initialInTime.split(':');
    final outTimeParts = initialOutTime.split(':');

    final inHourController = TextEditingController(text: inTimeParts[0]);
    final inMinController = TextEditingController(text: inTimeParts[1]);

    final outHourController = TextEditingController(text: outTimeParts[0]);
    final outMinController = TextEditingController(text: outTimeParts[1]);

    return Container(
      color: Colors.white, // ✅ 배경 하얗게
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            /// 날짜 표시
            Text(
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),

            /// 출근/퇴근 시간 입력
            _TimeInputRow('출근 시간', inHourController, inMinController),
            const SizedBox(height: 12),
            _TimeInputRow('퇴근 시간', outHourController, outMinController),
            const SizedBox(height: 24),

            /// 저장 버튼
            ElevatedButton.icon(
              icon: const Icon(Icons.save, size: 20),
              label: const Text(
                '저장',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                final inTime = '${inHourController.text.padLeft(2, '0')}:${inMinController.text.padLeft(2, '0')}';
                final outTime = '${outHourController.text.padLeft(2, '0')}:${outMinController.text.padLeft(2, '0')}';
                onSave(inTime, outTime);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),

            const SizedBox(height: 80), // ✅ 추가 여백
          ],
        ),
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
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
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
