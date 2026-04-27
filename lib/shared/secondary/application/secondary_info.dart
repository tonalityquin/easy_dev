import 'package:flutter/material.dart';

import '../../../app/models/capability.dart';
import '../../../features/account/pages/tablet/tablet_management.dart';
import '../../../features/account/pages/user/user_management.dart';
import '../../../features/location/pages/location_management.dart';
import '../../../features/monthly/page/monthly_parking_management.dart';
import '../../../features/payment/pages/bill_management.dart';
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

enum Section { user, tablet, monthly, location, bill, area, local, backend }

final Map<Section, CapSet> kSectionRequires = {
  Section.user: const <Capability>{},
  Section.location: const {Capability.location},
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

const SecondaryInfo tabLocation = SecondaryInfo(
  '구역 관리',
  LocationManagement(),
  Icon(Icons.location_on),
  requires: {Capability.location},
);

const SecondaryInfo tabTablet = SecondaryInfo(
  '태블릿 관리',
  TabletManagement(),
  Icon(Icons.tablet_mac),
  requires: {Capability.tablet},
);

const SecondaryInfo tabMonthly = SecondaryInfo(
  '월 주차 관리',
  MonthlyParkingManagement(),
  Icon(Icons.local_parking),
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

enum RoleType {
  dev,
  adminBillMonthly,
  adminBillMonthlyTablet,
  adminBill,
  adminBillTablet,
  adminCommon,
  adminCommonTablet,
  userLocationMonthly,
  userMonthly,
  userCommon,
  fieldCommon;

  String get label {
    switch (this) {
      case RoleType.dev:
        return '개발자(태블릿 O)';
      case RoleType.adminBillMonthly:
        return '모두 열린 관리자(태블릿 X)';
      case RoleType.adminBillMonthlyTablet:
        return '모두 열린 관리자(태블릿 O)';
      case RoleType.adminBill:
        return '정산만 열린 관리자(태블릿 X)';
      case RoleType.adminBillTablet:
        return '정산만 열린 관리자(태블릿 O)';
      case RoleType.adminCommon:
        return '공통 관리자(태블릿 X)';
      case RoleType.adminCommonTablet:
        return '공통 관리자(태블릿 O)';
      case RoleType.userLocationMonthly:
        return '모두 열린 유저(태블릿 X)';
      case RoleType.userMonthly:
        return '정기 주차만 열린 유저(태블릿 X)';
      case RoleType.userCommon:
        return '공통 유저(태블릿 X)';
      case RoleType.fieldCommon:
        return '공통 필드(태블릿 X)';
    }
  }

  static RoleType fromName(String name) {
    return RoleType.values.firstWhere(
      (e) => e.name == name,
      orElse: () {
        switch (name) {
          case 'adminBillMonthlyTablet':
            return RoleType.adminBillMonthlyTablet;
          case 'adminBillTablet':
            return RoleType.adminBillTablet;
          case 'adminCommonTablet':
            return RoleType.adminCommonTablet;
          case 'adminBillMonthly':
            return RoleType.adminBillMonthly;
          case 'adminBill':
            return RoleType.adminBill;
          case 'adminCommon':
            return RoleType.adminCommon;
          case 'userLocationMonthly':
            return RoleType.userLocationMonthly;
          case 'userMonthly':
            return RoleType.userMonthly;
          case 'fieldCommon':
            return RoleType.fieldCommon;
          case 'dev':
            return RoleType.dev;
          default:
            return RoleType.userCommon;
        }
      },
    );
  }
}

final Map<RoleType, Set<Section>> kRolePolicy = {
  RoleType.dev: {
    Section.local,
    Section.backend,
    Section.area,
    Section.user,
    Section.location,
    Section.tablet,
    Section.monthly,
    Section.bill,
  },
  RoleType.adminBillMonthly: {
    Section.local,
    Section.backend,
    Section.user,
    Section.location,
    Section.monthly,
    Section.bill,
  },
  RoleType.adminBillMonthlyTablet: {
    Section.local,
    Section.backend,
    Section.user,
    Section.location,
    Section.tablet,
    Section.monthly,
    Section.bill,
  },
  RoleType.adminBill: {
    Section.local,
    Section.backend,
    Section.user,
    Section.location,
    Section.bill,
  },
  RoleType.adminBillTablet: {
    Section.local,
    Section.backend,
    Section.user,
    Section.location,
    Section.tablet,
    Section.bill,
  },
  RoleType.adminCommon: {
    Section.local,
    Section.backend,
    Section.user,
    Section.location,
  },
  RoleType.adminCommonTablet: {
    Section.local,
    Section.backend,
    Section.user,
    Section.location,
    Section.tablet,
  },
  RoleType.userLocationMonthly: {
    Section.local,
    Section.backend,
    Section.location,
    Section.monthly,
  },
  RoleType.userMonthly: {
    Section.local,
    Section.backend,
    Section.monthly,
  },
  RoleType.userCommon: {
    Section.local,
    Section.backend,
  },
  RoleType.fieldCommon: {
    Section.local,
    Section.backend,
  },
};

final Map<Section, SecondaryInfo> kSectionTab = {
  Section.local: tabLocalData,
  Section.backend: tabBackend,
  Section.user: tabUser,
  Section.location: tabLocation,
  Section.tablet: tabTablet,
  Section.monthly: tabMonthly,
  Section.bill: tabBill,
  Section.area: tabAreaManage,
};
