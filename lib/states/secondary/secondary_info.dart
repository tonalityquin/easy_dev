import 'package:flutter/material.dart';


import '../../screens/secondary_package/office_mode_package/bill_management.dart';
import '../../screens/secondary_package/office_mode_package/location_management.dart';
import '../../screens/secondary_package/office_mode_package/monthly_parking_management.dart';
import '../../screens/secondary_package/office_mode_package/tablet_management.dart';
import '../../screens/secondary_package/office_mode_package/user_management.dart';
import '../../screens/secondary_package/dev_mode_package/back_end_controller.dart';
import '../../screens/secondary_package/dev_mode_package/area_management.dart';
import '../../screens/secondary_package/dev_mode_package/local_data.dart';


class SecondaryInfo {
  final String title;
  final Widget page;
  final Icon icon;


  const SecondaryInfo(this.title, this.page, this.icon);
}


const _backendController = SecondaryInfo('백엔드 컨트롤러', BackEndController(), Icon(Icons.free_breakfast));
const _localData = SecondaryInfo('로컬 데이터 관리', LocalData(), Icon(Icons.tab));
const _userManagement = SecondaryInfo('유저 관리', UserManagement(), Icon(Icons.people));
const _tabletManagement = SecondaryInfo('태블릿 관리', TabletManagement(), Icon(Icons.military_tech));
const _locationManagement = SecondaryInfo('구역 관리', LocationManagement(), Icon(Icons.location_on));
const _billManagement = SecondaryInfo('정산 관리', BillManagement(), Icon(Icons.adjust));
const _monthlyParking = SecondaryInfo('월 주차 관리', MonthlyParkingManagement(), Icon(Icons.local_parking));
const _areaManagement = SecondaryInfo('지역 추가', AreaManagement(), Icon(Icons.tab));


final List<SecondaryInfo> adminPages = [
  _backendController,
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
  _tabletManagement,
  _billManagement,
];


final List<SecondaryInfo> highManagePages = [
  _backendController,
  _userManagement,
  _tabletManagement,
  _billManagement,
];


final List<SecondaryInfo> devPages = [
  _backendController,
  _areaManagement,
  _localData,
];



