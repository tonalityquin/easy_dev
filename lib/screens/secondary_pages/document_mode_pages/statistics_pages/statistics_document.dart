import 'package:flutter/material.dart';
import '../../../../states/calendar/statistics_calendar_state.dart';
import '../../../../states/calendar/statistics_selected_date_state.dart';
import 'statistics_document_body.dart';
import 'package:provider/provider.dart';


class StatisticsDocument extends StatefulWidget {
  const StatisticsDocument({super.key});

  @override
  State<StatisticsDocument> createState() => _StatisticsDocumentState();
}

class _StatisticsDocumentState extends State<StatisticsDocument> {
  late StatisticsCalendarState calendar;

  @override
  void initState() {
    super.initState();
    calendar = StatisticsCalendarState();
  }

  @override
  Widget build(BuildContext context) {
    return StatisticsDocumentBody(
      calendar: calendar,
      onDateSelected: () {
        // 날짜 선택 상태를 글로벌 상태에 반영
        context.read<StatisticsSelectedDateState>().setSelectedDates(calendar.selectedDates);
      },
      refresh: () => setState(() {}),
    );
  }
}
