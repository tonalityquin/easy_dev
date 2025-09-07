import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

/// Google Calendar의 단일 이벤트를 카드 형태로 보여주는 위젯
class CalendarEventCard extends StatelessWidget {
  final calendar.Event event;

  const CalendarEventCard({super.key, required this.event});

  /// 이벤트 description 문자열에서 진행률(progress:xx)을 추출
  int _getProgress(String? desc) {
    final match = RegExp(r'progress:(\d{1,3})').firstMatch(desc ?? '');
    if (match != null) {
      return int.tryParse(match.group(1) ?? '')?.clamp(0, 100) ?? 0;
    }
    return 0;
  }

  /// 체크리스트 항목을 description 문자열에서 추출
  /// - [x] or [ ] 형태의 마크다운을 분석하여 리스트 반환
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

        // 이벤트 제목
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),

        // 진행률 표시 영역
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

        // 확장 아이콘
        trailing: const Icon(Icons.expand_more),

        // 카드 클릭 시 상세 바텀시트 표시
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
                        // 이벤트 제목
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 체크리스트 또는 description 표시
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

                        // 바텀시트 닫기 버튼
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
