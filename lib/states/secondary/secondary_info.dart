import 'package:flutter/material.dart';

import '../../screens/secondary_pages/dev_mode_pages/local_data.dart';
import '../../screens/secondary_pages/field_leader_pages/dash_board/dash_board_screen.dart';

import '../../screens/secondary_pages/field_user_pages/fielder_dash_board_screen.dart';
import '../../screens/secondary_pages/office_mode_pages/bill_management.dart';
import '../../screens/secondary_pages/field_leader_pages/location_management.dart';
import '../../screens/secondary_pages/office_mode_pages/shortcut_management.dart';
import '../../screens/secondary_pages/office_mode_pages/user_management.dart';

import '../../screens/secondary_pages/document_mode_pages/attendance_pages/easter_egg.dart';
import '../../screens/secondary_pages/document_mode_pages/break_pages/back_end_controller.dart';

import '../../screens/secondary_pages/dev_mode_pages/area_management.dart';

class SecondaryInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const SecondaryInfo(this.title, this.page, this.icon);
}

final List<SecondaryInfo> adminPages = [
  SecondaryInfo('유저 관리', UserManagement(), Icon(Icons.people)),
  SecondaryInfo('로컬 데이터 관리', LocalData(), Icon(Icons.tab)),
  SecondaryInfo('필드 대시보드', FielderDashBoardScreen(), Icon(Icons.dashboard)),
  SecondaryInfo('공통 대시보드', DashBoardScreen(), Icon(Icons.dashboard)),
  SecondaryInfo('구역 관리', LocationManagement(), Icon(Icons.location_on)),

  SecondaryInfo('정산 관리', BillManagement(), Icon(Icons.adjust)),
  SecondaryInfo('쇼트컷 관리', ShortcutManagement(), Icon(Icons.adjust)),
  SecondaryInfo('이스터 에그', EasterEgg(), Icon(Icons.badge)),
  SecondaryInfo('백엔드 컨트롤러', BackEndController(), Icon(Icons.free_breakfast)),
  SecondaryInfo('지역 추가', AreaManagement(), Icon(Icons.tab)),
];

final List<SecondaryInfo> lowUserModePages = [
  SecondaryInfo('대시보드', FielderDashBoardScreen(), Icon(Icons.dashboard)),
  SecondaryInfo('로컬 데이터 관리', LocalData(), Icon(Icons.tab)),
];
final List<SecondaryInfo> middleUserModePages = [
  SecondaryInfo('대시보드', DashBoardScreen(), Icon(Icons.dashboard)),
  SecondaryInfo('구역 관리', LocationManagement(), Icon(Icons.location_on)),
  SecondaryInfo('로컬 데이터 관리', LocalData(), Icon(Icons.tab)),
];

final List<SecondaryInfo> highUserModePages = [
  SecondaryInfo('대시보드', DashBoardScreen(), Icon(Icons.dashboard)),
  SecondaryInfo('구역 관리', LocationManagement(), Icon(Icons.location_on)),
  SecondaryInfo('로컬 데이터 관리', LocalData(), Icon(Icons.tab)),
];

final List<SecondaryInfo> managerFieldModePages = [
  SecondaryInfo('대시보드', DashBoardScreen(), Icon(Icons.dashboard)),
  SecondaryInfo('구역 관리', LocationManagement(), Icon(Icons.location_on)),
  SecondaryInfo('로컬 데이터 관리', LocalData(), Icon(Icons.tab)),
];

final List<SecondaryInfo> lowMiddleManagePages = [
  SecondaryInfo('유저 관리', UserManagement(), Icon(Icons.people)),
  SecondaryInfo('정산 관리', BillManagement(), Icon(Icons.adjust)),
];

final List<SecondaryInfo> highManagePages = [
  SecondaryInfo('유저 관리', UserManagement(), Icon(Icons.people)),
  SecondaryInfo('정산 관리', BillManagement(), Icon(Icons.adjust)),
  SecondaryInfo('쇼트컷 관리', ShortcutManagement(), Icon(Icons.adjust)),
];

/// 🔹 Document Mode Pages
final List<SecondaryInfo> documentPages = [
  SecondaryInfo('이스터 에그', EasterEgg(), Icon(Icons.badge)),
  SecondaryInfo('백엔드 컨트롤러', BackEndController(), Icon(Icons.free_breakfast)),
];

/// 🔹 Dev Mode Pages
final List<SecondaryInfo> devPages = [
  SecondaryInfo('지역 추가', AreaManagement(), Icon(Icons.tab)),
  SecondaryInfo('로컬 데이터 관리', LocalData(), Icon(Icons.tab)),
];
