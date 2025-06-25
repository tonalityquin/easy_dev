import 'package:flutter/material.dart';

// Field Mode Pages
import '../../screens/secondary_pages/dev_mode_pages/local_data.dart';
import '../../screens/secondary_pages/field_mode_pages/dash_board/dash_board_screen.dart';
import '../../screens/secondary_pages/field_mode_pages/docu_sign.dart';
import '../../screens/secondary_pages/field_mode_pages/chat.dart';
import '../../screens/secondary_pages/field_mode_pages/wireless.dart';

// Office Mode Pages
import '../../screens/secondary_pages/office_mode_pages/bill_management.dart';
import '../../screens/secondary_pages/office_mode_pages/office_calender.dart';
import '../../screens/secondary_pages/office_mode_pages/location_management.dart';
import '../../screens/secondary_pages/office_mode_pages/status_management.dart';
import '../../screens/secondary_pages/office_mode_pages/user_management.dart';

// Document Mode Pages
import '../../screens/secondary_pages/document_mode_pages/attendance_pages/worker_attendance_document.dart';
import '../../screens/secondary_pages/document_mode_pages/break_pages/worker_break_document.dart';

// Dev Mode Pages
import '../../screens/secondary_pages/dev_mode_pages/area_management.dart';

class SecondaryInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const SecondaryInfo(this.title, this.page, this.icon);
}

/// 🔹 Field Mode Pages
final List<SecondaryInfo> fieldModePages = [
  SecondaryInfo('대시보드', DashBoardScreen(), Icon(Icons.dashboard)),
  SecondaryInfo('Wireless', Wireless(), Icon(Icons.wifi)),
  SecondaryInfo('Chat', Chat(), Icon(Icons.message)),
  SecondaryInfo('DocuSign', DocuSign(), Icon(Icons.document_scanner)),
];

/// 🔹 Office Mode Pages
final List<SecondaryInfo> officeModePages = [
  SecondaryInfo('유저 관리', UserManagement(), Icon(Icons.people)),
  SecondaryInfo('구역 관리', LocationManagement(), Icon(Icons.location_on)),
  SecondaryInfo('정산 관리', BillManagement(), Icon(Icons.adjust)),
  SecondaryInfo('상태창 관리', StatusManagement(), Icon(Icons.tune)),
  SecondaryInfo('투두 달력', OfficeCalenderPage(), Icon(Icons.calendar_today)),
];

/// 🔹 Document Mode Pages
final List<SecondaryInfo> documentPages = [
  SecondaryInfo('출퇴근 문서', WorkerAttendanceDocument(), Icon(Icons.badge)),
  SecondaryInfo('휴게시간 문서', WorkerBreakDocument(), Icon(Icons.free_breakfast )),
];

/// 🔹 Dev Mode Pages
final List<SecondaryInfo> devPages = [
  SecondaryInfo('지역 추가', AreaManagement(), Icon(Icons.tab)),
  SecondaryInfo('로컬 데이터 관리', LocalData(), Icon(Icons.tab)),
];