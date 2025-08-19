import 'package:flutter/material.dart';

import '../../screens/secondary_pages/dev_mode_pages/local_data.dart';
import '../../screens/secondary_pages/office_mode_pages/bill_management.dart';
import '../../screens/secondary_pages/office_mode_pages/location_management.dart';
import '../../screens/secondary_pages/office_mode_pages/monthly_parking_management.dart';
import '../../screens/secondary_pages/office_mode_pages/user_management.dart';
import '../../screens/secondary_pages/dev_mode_pages/easter_egg.dart';
import '../../screens/secondary_pages/dev_mode_pages/back_end_controller.dart';
import '../../screens/secondary_pages/dev_mode_pages/area_management.dart';

class SecondaryInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const SecondaryInfo(this.title, this.page, this.icon);
}

const _easterEgg = SecondaryInfo('이스터 에그', EasterEgg(), Icon(Icons.badge));
const _backendController = SecondaryInfo('백엔드 컨트롤러', BackEndController(), Icon(Icons.free_breakfast));
const _localData = SecondaryInfo('로컬 데이터 관리', LocalData(), Icon(Icons.tab));
const _userManagement = SecondaryInfo('유저 관리', UserManagement(), Icon(Icons.people));
const _locationManagement = SecondaryInfo('구역 관리', LocationManagement(), Icon(Icons.location_on));
const _billManagement = SecondaryInfo('정산 관리', BillManagement(), Icon(Icons.adjust));
const _monthlyParking = SecondaryInfo('월 주차 관리', MonthlyParkingManagement(), Icon(Icons.local_parking));
const _areaManagement = SecondaryInfo('지역 추가', AreaManagement(), Icon(Icons.tab));

final List<SecondaryInfo> adminPages = [
  _backendController,
  _easterEgg,
  _localData,
  _userManagement,
  _locationManagement,
  _billManagement,
  _areaManagement,
];

final List<SecondaryInfo> lowUserModePages = [
  _backendController,
  _localData,
  _monthlyParking,
];

final List<SecondaryInfo> middleUserModePages = [
  _backendController,
  _locationManagement,
  _monthlyParking,
  _localData,
];

final List<SecondaryInfo> highUserModePages = [
  _backendController,
  _locationManagement,
  _monthlyParking,
  _localData,
];

final List<SecondaryInfo> managerFieldModePages = [
  _backendController,
  _locationManagement,
  _monthlyParking,
  _localData,
];

final List<SecondaryInfo> lowMiddleManagePages = [
  _backendController,
  _userManagement,
  _billManagement,
];

final List<SecondaryInfo> highManagePages = [
  _backendController,
  _userManagement,
  _billManagement,
];

final List<SecondaryInfo> devPages = [
  _backendController,
  _easterEgg,
  _areaManagement,
  _localData,
];
