import 'package:flutter/material.dart';

import '../../../app/models/account_role.dart';
import '../../../app/models/capability.dart';
export '../../../app/models/account_role.dart';
import '../../../features/account/pages/tablet/tablet_management.dart';
import '../../../features/account/pages/user/user_management.dart';
import '../../../features/location/pages/location_management.dart';
import '../../../features/monthly/page/monthly_parking_management.dart';
import '../../../features/payment/pages/bill_management.dart';
import '../../../features/sector/pages/sector_management.dart';
import '../../../features/rule/pages/rule_management.dart';
import '../pages/sheets/area_management.dart';
import '../pages/sheets/back_end_controller.dart';
import '../pages/sheets/dash_board_setting.dart';

class SecondaryInfo {
  final String title;
  final Widget page;
  final Icon icon;
  final CapSet requires;

  const SecondaryInfo(
    this.title,
    this.page,
    this.icon, {
    this.requires = const <Capability>{},
  });
}

enum Section { user, sector, location, rule, tablet, monthly, bill, area, local, backend }

final Map<Section, CapSet> kSectionRequires = {
  Section.user: const <Capability>{},
  Section.sector: const {Capability.sector},
  Section.location: const {Capability.location},
  Section.rule: const {Capability.rule},
  Section.tablet: const {Capability.tablet},
  Section.monthly: const {Capability.monthly},
  Section.bill: const {Capability.bill},
  Section.area: const <Capability>{},
  Section.local: const <Capability>{},
  Section.backend: const <Capability>{},
};

const SecondaryInfo tabLocalData = SecondaryInfo(
  '대시보드 설정',
  DashboardSetting(),
  Icon(Icons.settings),
);

const SecondaryInfo tabBackend = SecondaryInfo(
  '백엔드 컨트롤러',
  BackEndController(),
  Icon(Icons.settings_ethernet),
);

const SecondaryInfo tabUser = SecondaryInfo(
  '유저 관리',
  UserManagement(),
  Icon(Icons.people),
);

const SecondaryInfo tabSector = SecondaryInfo(
  '섹터 관리',
  SectorManagement(),
  Icon(Icons.hub_rounded),
  requires: {Capability.sector},
);

const SecondaryInfo tabLocation = SecondaryInfo(
  '구역 관리',
  LocationManagement(),
  Icon(Icons.location_on),
  requires: {Capability.location},
);

const SecondaryInfo tabRule = SecondaryInfo(
  '업무 규칙 관리',
  RuleManagement(),
  Icon(Icons.rule_rounded),
  requires: {Capability.rule},
);

const SecondaryInfo tabTablet = SecondaryInfo(
  '태블릿 관리',
  TabletManagement(),
  Icon(Icons.tablet_mac),
  requires: {Capability.tablet},
);

const SecondaryInfo tabMonthly = SecondaryInfo(
  '정기 주차 관리',
  MonthlyParkingManagement(),
  Icon(Icons.local_parking_rounded),
  requires: {Capability.monthly},
);

const SecondaryInfo tabBill = SecondaryInfo(
  '정산 관리',
  BillManagement(),
  Icon(Icons.receipt_long),
  requires: {Capability.bill},
);

const SecondaryInfo tabAreaManage = SecondaryInfo(
  '지역 추가',
  AreaManagement(),
  Icon(Icons.add_location_alt),
);

final Map<RoleType, Set<Section>> kRolePolicy = {
  RoleType.ceo: {
    Section.user, Section.sector, Section.location, Section.rule,
    Section.tablet, Section.monthly, Section.bill,
  },
  RoleType.headAdmin: {
    Section.user, Section.sector, Section.location, Section.rule,
    Section.tablet, Section.monthly, Section.bill,
  },
  RoleType.headStaff: {
    Section.user, Section.sector, Section.location, Section.rule,
    Section.tablet, Section.monthly, Section.bill,
  },
  RoleType.branchAdmin: <Section>{},
  RoleType.branchProAdmin: {
    Section.user, Section.sector, Section.location,
    Section.tablet, Section.monthly, Section.bill,
  },
  RoleType.branchStaff: <Section>{},
  RoleType.branchProStaff: {Section.monthly, Section.bill},
};

final Map<Section, SecondaryInfo> kSectionTab = {
  Section.local: tabLocalData,
  Section.backend: tabBackend,
  Section.user: tabUser,
  Section.sector: tabSector,
  Section.location: tabLocation,
  Section.rule: tabRule,
  Section.tablet: tabTablet,
  Section.monthly: tabMonthly,
  Section.bill: tabBill,
  Section.area: tabAreaManage,
};
