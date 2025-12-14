// lib/states/secondary/secondary_info.dart
//
// Secondary 탭 정의와 "역할 정책 + capability 요구"를 한 곳에 정리.
// - 공통 탭(대시보드 설정/백엔드)은 항상 표시 가능(별도 Capability 불요)
// - 선택 탭(태블릿/월주차/정산)은 Capability 필요
// - 역할(RoleType)별로 어느 섹션(Section)을 허용할지 정책 맵으로 관리
//
// 요구 정책 반영:
//  * userCommon / fieldCommon: '유저 관리', '구역 관리'는 노출되지 않아야 함
//  * adminCommon: 공통 탭(유저/구역)만 노출 (tablet/monthly/bill 탭은 제외)
//  * 역할에 “Tablet”이 붙지 않은 변형(태블릿 X)은 Section.tablet을 허용하지 않음
//
// 이 파일은 "탭 구성 규칙"만 제공하며, 실사용(계산/반영)은 SecondaryPage 에서 수행합니다.
//
import 'package:flutter/material.dart';

import '../../models/capability.dart';

import '../../screens/service_mode/secondary_package/office_mode_package/bill_management.dart';
import '../../screens/service_mode/secondary_package/office_mode_package/location_management.dart';
import '../../screens/service_mode/secondary_package/office_mode_package/monthly_parking_management.dart';
import '../../screens/service_mode/secondary_package/office_mode_package/tablet_management.dart';
import '../../screens/service_mode/secondary_package/office_mode_package/user_management.dart';
import '../../screens/service_mode/secondary_package/dev_mode_package/back_end_controller.dart';
import '../../screens/service_mode/secondary_package/dev_mode_package/area_management.dart';
// 리팩토링: LocalData 대신 DashboardSetting 사용
import '../../screens/service_mode/secondary_package/dev_mode_package/dash_board_setting.dart';

/// 앱에서 보여줄 하나의 탭(항목)
class SecondaryInfo {
  final String title;
  final Widget page;
  final Icon icon;

  /// 이 탭이 의미 있으려면 필요한 Capability 집합(비어 있으면 항상 가능)
  final CapSet requires;

  const SecondaryInfo(
      this.title,
      this.page,
      this.icon, {
        this.requires = const <Capability>{},
      });
}

// ── 섹션 정의(역할 정책의 단위) ────────────────────────────────────────────────
/// 화면에서 의미 있는 "기능 섹션" 단위
enum Section { user, tablet, monthly, location, bill, area, local, backend }

/// 섹션별 Capability 요구 사항(공통은 빈 집합)
final Map<Section, CapSet> kSectionRequires = {
  Section.user: const <Capability>{},
  Section.location: const <Capability>{},
  Section.tablet: const {Capability.tablet},
  Section.monthly: const {Capability.monthly},
  Section.bill: const {Capability.bill},
  // 개발/로컬/백엔드 섹션은 요구 없음
  Section.area: const <Capability>{},
  Section.local: const <Capability>{},
  Section.backend: const <Capability>{},
};

// ── 탭 위젯 정의(한 곳에서 재사용) ─────────────────────────────────────────────
/// 리팩토링: 기존 '로컬 데이터 관리' → '대시보드 설정' + DashboardSetting()
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

// ── 역할 정의 ────────────────────────────────────────────────────────────────
/// 프로젝트 전역에서 쓰는 RoleType
/// (라벨과 fromName까지 enum 내부에 포함)
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

  /// 한국어 라벨 반환
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

  /// 이름 문자열에서 RoleType enum으로 변환 (방어적 매핑)
  static RoleType fromName(String name) {
    return RoleType.values.firstWhere(
          (e) => e.name == name,
      orElse: () {
        // 과거 호환 / 오타 방지 기본값: 가장 제한적인 공통 유저
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

/// 역할 → 허용 섹션
///
/// 규칙:
/// - “Tablet” 변형인 역할만 Section.tablet 허용
/// - userCommon / fieldCommon 은 '유저 관리', '구역 관리' 노출 금지
/// - adminCommon 은 공통 탭(유저/구역)만 노출 (tablet/monthly/bill 제외)
final Map<RoleType, Set<Section>> kRolePolicy = {
  RoleType.dev: {
    Section.local,
    Section.backend,
    Section.area, // 개발만 지역 추가
    Section.user,
    Section.location,
    Section.tablet, // 태블릿 O
    Section.monthly,
    Section.bill,
  },

  // 모두 열린 관리자
  RoleType.adminBillMonthly: {
    Section.local,
    Section.backend,
    Section.user,
    Section.location,
    // tablet 제외(태블릿 X)
    Section.monthly,
    Section.bill,
  },
  RoleType.adminBillMonthlyTablet: {
    Section.local,
    Section.backend,
    Section.user,
    Section.location,
    Section.tablet, // 태블릿 O
    Section.monthly,
    Section.bill,
  },

  // 정산만 열린 관리자
  RoleType.adminBill: {
    Section.local,
    Section.backend,
    Section.user,
    Section.location,
    // tablet 제외(태블릿 X)
    Section.bill,
  },
  RoleType.adminBillTablet: {
    Section.local,
    Section.backend,
    Section.user,
    Section.location,
    Section.tablet, // 태블릿 O
    Section.bill,
  },

  // 공통 관리자 (tablet/monthly/bill 제외)
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
    Section.tablet, // 태블릿 O
  },

  // 유저(공간+정기)
  RoleType.userLocationMonthly: {
    Section.local,
    Section.backend,
    Section.location,
    Section.monthly,
  },

  // 유저(정기)
  RoleType.userMonthly: {
    Section.local,
    Section.backend,
    Section.monthly,
  },

  // 공통 유저 / 공통 필드 → 공통 탭만
  RoleType.userCommon: {
    Section.local,
    Section.backend,
  },
  RoleType.fieldCommon: {
    Section.local,
    Section.backend,
  },
};

/// 섹션 → 탭 위젯 매핑
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
