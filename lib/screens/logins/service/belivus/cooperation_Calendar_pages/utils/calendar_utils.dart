import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

/// Google Calendar colorId → Flutter Color 매핑
final Map<String, Color> googleColorMap = {
  "1": Colors.blue,
  "2": Colors.green,
  "3": Colors.purple,
  "4": Colors.red,
  "5": Colors.yellow,
  "6": Colors.orange,
  "7": Colors.teal,
  "8": Colors.grey,
  "9": Colors.brown,
  "10": Colors.cyan,
  "11": Colors.indigo,
};

/// 진행률 추출
int getProgress(String? desc) {
  final match = RegExp(r'progress:(\d{1,3})').firstMatch(desc ?? '');
  if (match != null) {
    return int.tryParse(match.group(1) ?? '')?.clamp(0, 100) ?? 0;
  }
  return 0;
}

/// 캘린더 셀 마커
Widget buildEventMarker(calendar.Event event) {
  final progress = getProgress(event.description);
  final colorId = event.colorId?.trim();
  final bgColor = googleColorMap[colorId] ?? Colors.indigo;
  final title = event.summary?.trim() ?? '무제';

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 1),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      '$title ($progress%)',
      style: const TextStyle(
        fontSize: 10,
        color: Colors.white,
      ),
      overflow: TextOverflow.ellipsis,
    ),
  );
}
