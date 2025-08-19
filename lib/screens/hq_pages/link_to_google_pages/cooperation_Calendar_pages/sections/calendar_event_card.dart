import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

class CalendarEventCard extends StatelessWidget {
  final calendar.Event event;

  const CalendarEventCard({super.key, required this.event});

  int _getProgress(String? desc) {
    final match = RegExp(r'progress:(\d{1,3})').firstMatch(desc ?? '');
    if (match != null) {
      return int.tryParse(match.group(1) ?? '')?.clamp(0, 100) ?? 0;
    }
    return 0;
  }

  List<Map<String, dynamic>> _parseChecklist(String? desc) {
    if (desc == null) return [];
    final lines = desc.split('\n');
    return lines.where((line) => line.trim().startsWith('- [')).map((line) {
      final checked = line.contains('- [x]');
      final text = line.replaceFirst(RegExp(r'- \[[ x]\]'), '').trim();
      return {'text': text, 'checked': checked};
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _getProgress(event.description);
    final desc = event.description?.trim() ?? '';
    final checklist = _parseChecklist(desc);
    final title = event.summary?.trim() ?? '무제';

    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 32,
                    width: 32,
                    child: CircularProgressIndicator(
                      value: progress / 100,
                      strokeWidth: 4,
                      backgroundColor: Colors.grey.shade200,
                      color: Colors.indigo,
                    ),
                  ),
                  Text(
                    '$progress%',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              const Text("진행률", style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        trailing: const Icon(Icons.expand_more),
        onTap: () {
          if (desc.isNotEmpty) {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.white,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (context) {
                return FractionallySizedBox(
                  heightFactor: 0.6,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            child: checklist.isEmpty
                                ? Text(
                                    desc,
                                    style: const TextStyle(fontSize: 14),
                                  )
                                : Column(
                                    children: checklist
                                        .map((item) => CheckboxListTile(
                                              value: item['checked'],
                                              onChanged: null, // 읽기 전용
                                              title: Text(item['text']),
                                              controlAffinity: ListTileControlAffinity.leading,
                                            ))
                                        .toList(),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('닫기'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
