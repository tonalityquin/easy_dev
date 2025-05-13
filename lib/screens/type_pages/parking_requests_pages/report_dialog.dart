import 'package:flutter/material.dart';

class ParkingReportDialog extends StatefulWidget {
  final void Function(String reportType, String content) onReport;

  const ParkingReportDialog({super.key, required this.onReport});

  @override
  State<ParkingReportDialog> createState() => _ParkingReportDialogState();
}

class _ParkingReportDialogState extends State<ParkingReportDialog> {
  int _selectedTabIndex = 0;
  final TextEditingController _vehicleCountController = TextEditingController();
  final TextEditingController _startReportController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('업무 보고'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToggleButtons(
            isSelected: [_selectedTabIndex == 0, _selectedTabIndex == 1],
            onPressed: (index) {
              setState(() {
                _selectedTabIndex = index;
              });
            },
            children: const [
              Padding(padding: EdgeInsets.all(8), child: Text('업무 시작 보고')),
              Padding(padding: EdgeInsets.all(8), child: Text('업무 종료 보고')),
            ],
          ),
          const SizedBox(height: 16),
          if (_selectedTabIndex == 0)
            TextField(
              controller: _startReportController,
              decoration: const InputDecoration(
                labelText: '업무 시작 내용',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          if (_selectedTabIndex == 1)
            TextField(
              controller: _vehicleCountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '입차 차량 수',
                border: OutlineInputBorder(),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            String type = _selectedTabIndex == 0 ? 'start' : 'end';
            String content =
                _selectedTabIndex == 0 ? _startReportController.text.trim() : _vehicleCountController.text.trim();

            if (content.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('내용을 입력해주세요.')),
              );
              return;
            }

            widget.onReport(type, content);
            Navigator.pop(context);
          },
          child: const Text('Report'),
        ),
      ],
    );
  }
}
