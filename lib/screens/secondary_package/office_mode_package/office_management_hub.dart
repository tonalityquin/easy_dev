// lib/screens/secondary_package/office_mode_package/office_management_hub.dart
//
// 오피스 관리 허브(한 화면에서 탭으로 전환)
// - 포함 섹션: 유저 관리, 태블릿 관리, 월 주차 관리, 구역 관리, 정산 관리
// - 모드 정책과 지역 capability(tablet/monthly/bill)에 따라 탭 노출 제어
//
// 정책 규칙(현재 프로젝트 정책과 동일):
// - adminCommon: [유저, 구역]만 허용 (tablet/monthly/bill은 금지)
// - adminBill  : [유저, 구역, 정산] 허용 + (tablet은 capability 있으면 허용) / monthly는 금지
// - adminBillMonthly: [유저, 구역, 정산, 월주차] 허용 + (tablet은 capability 있으면 허용)
//
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/capability.dart';
import '../../../states/area/area_state.dart';

// 기존 개별 페이지들
import 'user_management.dart';
import 'tablet_management.dart';
import 'monthly_parking_management.dart';
import 'location_management.dart';
import 'bill_management.dart';

enum OfficeHubPolicy {
  adminCommon,
  adminBill,
  adminBillMonthly,
}

class OfficeManagementHub extends StatelessWidget {
  final OfficeHubPolicy policy;
  final int? initialIndex;

  const OfficeManagementHub({
    super.key,
    required this.policy,
    this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    final caps = context.select<AreaState, CapSet>((s) => s.capabilitiesOfCurrentArea);

    // 정책별 허용 섹션(정적)
    final allowedByPolicy = <_SectionId, bool>{
      _SectionId.user: true,
      _SectionId.location: true,
      _SectionId.tablet: policy != OfficeHubPolicy.adminCommon, // adminCommon 금지
      _SectionId.monthly: policy == OfficeHubPolicy.adminBillMonthly, // adminCommon/adminBill 금지
      _SectionId.bill: policy != OfficeHubPolicy.adminCommon, // adminCommon 금지
    };

    // 섹션 정의(각 섹션의 capability 요구)
    final sections = <_SectionDef>[
      _SectionDef(
        id: _SectionId.user,
        title: '유저 관리',
        icon: const Icon(Icons.people),
        child: const UserManagement(),
        requires: const <Capability>{}, // 항상 허용 (단, policy에서만 제어)
      ),
      _SectionDef(
        id: _SectionId.tablet,
        title: '태블릿 관리',
        icon: const Icon(Icons.tablet_mac),
        child: const TabletManagement(),
        requires: const {Capability.tablet}, // tablet 필요
      ),
      _SectionDef(
        id: _SectionId.monthly,
        title: '월 주차 관리',
        icon: const Icon(Icons.local_parking),
        child: const MonthlyParkingManagement(),
        requires: const {Capability.monthly}, // monthly 필요
      ),
      _SectionDef(
        id: _SectionId.location,
        title: '구역 관리',
        icon: const Icon(Icons.location_on),
        child: const LocationManagement(),
        requires: const <Capability>{}, // 항상 허용 (단, policy에서만 제어)
      ),
      _SectionDef(
        id: _SectionId.bill,
        title: '정산 관리',
        icon: const Icon(Icons.receipt_long),
        child: const BillManagement(),
        requires: const {Capability.bill}, // bill 필요
      ),
    ];

    // 정책 + capability로 최종 탭 리스트 구성
    final active = sections.where((s) {
      final policyOk = allowedByPolicy[s.id] ?? false;
      final capsOk = Cap.supports(caps, s.requires);
      return policyOk && capsOk;
    }).toList(growable: false);

    // 최소 보장: 정책상 user/location만 허용되는 경우가 있으므로, active가 비면 안전 디폴트
    final tabs = active.isNotEmpty
        ? active
        : sections.where((s) => s.id == _SectionId.user || s.id == _SectionId.location).toList();

    // DefaultTabController가 탭 수 변화에 안전하게 재생성되도록 Key 적용
    final ctrlKey = ValueKey('officehub_${tabs.map((t) => t.title).join("_")}');

    return DefaultTabController(
      key: ctrlKey,
      length: tabs.length,
      initialIndex: (initialIndex != null && initialIndex! < tabs.length) ? initialIndex! : 0,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black87,
          title: const Text('오피스 관리', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          bottom: TabBar(
            isScrollable: true,
            tabs: tabs.map((t) => Tab(icon: t.icon, text: t.title)).toList(),
          ),
        ),
        body: TabBarView(
          children: tabs
              .map((t) => KeyedSubtree(key: PageStorageKey('hub_${t.title}'), child: t.child))
              .toList(),
        ),
      ),
    );
  }
}

enum _SectionId { user, tablet, monthly, location, bill }

class _SectionDef {
  final _SectionId id;
  final String title;
  final Icon icon;
  final Widget child;
  final CapSet requires;

  const _SectionDef({
    required this.id,
    required this.title,
    required this.icon,
    required this.child,
    required this.requires,
  });
}
