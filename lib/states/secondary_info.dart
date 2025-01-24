import 'package:flutter/material.dart';
import '../screens/secondary_pages/field_mode_pages/dash_board.dart'; // 대시보드 페이지
import '../screens/secondary_pages/field_mode_pages/docu_sign.dart'; // 관리 페이지
import '../screens/secondary_pages/field_mode_pages/chat.dart'; // 채팅 페이지
import '../screens/secondary_pages/field_mode_pages/wireless.dart'; // 무전 페이지
import '../screens/secondary_pages/office_mode_pages/adjustment_management.dart'; // 조정 페이지
import '../screens/secondary_pages/office_mode_pages/calender.dart'; // 일정 관리 페이지
import '../screens/secondary_pages/office_mode_pages/location_management.dart'; // 위치 관리 페이지
import '../screens/secondary_pages/office_mode_pages/status_management.dart';
import '../screens/secondary_pages/office_mode_pages/user_management.dart'; // 사용자 관리 페이지

/// 페이지 정보를 나타내는 클래스
/// - 각 페이지의 타이틀, 위젯, 아이콘 정보를 포함
class SecondaryInfo {
  final String title; // 페이지 타이틀
  final Widget page; // 해당 페이지를 나타내는 위젯
  final Icon icon; // 페이지를 나타내는 아이콘

  /// SecondaryInfo 생성자
  /// - [title]: 페이지 이름
  /// - [page]: 해당 페이지 위젯
  /// - [icon]: 페이지를 나타내는 아이콘
  SecondaryInfo(this.title, this.page, this.icon);
}

/// Field Mode에 해당하는 페이지 목록
final List<SecondaryInfo> fieldModePages = [
  SecondaryInfo('DashBoard', const DashBoard(), Icon(Icons.dashboard)), // 대시보드
  SecondaryInfo('Wireless', const Wireless(), Icon(Icons.wifi)), // 무전 페이지
  SecondaryInfo('Chat', const Chat(), Icon(Icons.message)), // 채팅 페이지
  SecondaryInfo('DocuSign', const DocuSign(), Icon(Icons.document_scanner)), // 문서 서명 페이지
];

/// Office Mode에 해당하는 페이지 목록
final List<SecondaryInfo> officeModePages = [
  SecondaryInfo('사용자 관리', const UserManagement(), Icon(Icons.people)), // 사용자 관리
  SecondaryInfo('구역 관리', const LocationManagement(), Icon(Icons.location_on)), // 위치 관리
  SecondaryInfo('정산 관리', const AdjustmentManagement(), Icon(Icons.tune)), // 정산 관리
  SecondaryInfo('상태 관리', const StatusManagement(), Icon(Icons.tune)), // 차량 상태 관리
  SecondaryInfo('Calendar', const Calender(), Icon(Icons.calendar_today)), // 일정 관리
];
