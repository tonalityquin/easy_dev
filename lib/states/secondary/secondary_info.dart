import 'package:flutter/material.dart';
import '../../screens/secondary_pages/field_mode_pages/dash_board.dart';
import '../../screens/secondary_pages/field_mode_pages/docu_sign.dart';
import '../../screens/secondary_pages/field_mode_pages/chat.dart';
import '../../screens/secondary_pages/field_mode_pages/wireless.dart';
import '../../screens/secondary_pages/office_mode_pages/adjustment_management.dart';
import '../../screens/secondary_pages/office_mode_pages/calender.dart';
import '../../screens/secondary_pages/office_mode_pages/location_management.dart';
import '../../screens/secondary_pages/office_mode_pages/status_management.dart';
import '../../screens/secondary_pages/office_mode_pages/user_management.dart';
import '../../screens/secondary_pages/statistics_mode_pages/calendar_type_statistics.dart';
import '../../screens/secondary_pages/statistics_mode_pages/graph_type_statistics.dart';

class SecondaryInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const SecondaryInfo(this.title, this.page, this.icon);
}

final List<SecondaryInfo> fieldModePages = [
  SecondaryInfo('DashBoard', DashBoard(), Icon(Icons.dashboard)),
  SecondaryInfo('Wireless', Wireless(), Icon(Icons.wifi)),
  SecondaryInfo('Chat', Chat(), Icon(Icons.message)),
  SecondaryInfo('DocuSign', DocuSign(), Icon(Icons.document_scanner)),
];
final List<SecondaryInfo> officeModePages = [
  SecondaryInfo('유저 관리', UserManagement(), Icon(Icons.people)),
  SecondaryInfo('구역 관리', LocationManagement(), Icon(Icons.location_on)),
  SecondaryInfo('정산 관리', AdjustmentManagement(), Icon(Icons.adjust)),
  SecondaryInfo('상태창 관리', StatusManagement(), Icon(Icons.tune)),
  SecondaryInfo('투두 달력', Calendar(), Icon(Icons.calendar_today)),
];
final List<SecondaryInfo> statisticsPages = [
  SecondaryInfo('달력 타입', CalendarTypeStatistics(), Icon(Icons.calendar_month)),
  SecondaryInfo('그래프 타입', GraphTypeStatistics(), Icon(Icons.auto_graph_sharp)),
];
