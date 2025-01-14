import 'package:flutter/material.dart';
import '../screens/secondary_pages/field_mode_pages/dash_board.dart'; // 대시보드 페이지
import '../screens/secondary_pages/field_mode_pages/docu_sign.dart'; // 관리 페이지
import '../screens/secondary_pages/field_mode_pages/chat.dart'; // 채팅 페이지
import '../screens/secondary_pages/field_mode_pages/wireless.dart'; // 무전 페이지
import '../screens/secondary_pages/office_mode_pages/adjustment.dart'; // 조정 페이지
import '../screens/secondary_pages/office_mode_pages/calander.dart'; // 일정 관리 페이지
import '../screens/secondary_pages/office_mode_pages/location_management.dart'; // 위치 관리 페이지
import '../screens/secondary_pages/office_mode_pages/user_management.dart'; // 사용자 관리 페이지

/// **SecondaryInfo 클래스**
// - 화면 정보를 저장하는 데이터 클래스
// - 각 화면의 타이틀, 페이지 위젯, 아이콘을 포함
class SecondaryInfo {
  final String title; // 페이지 타이틀
  final Widget page; // 해당 페이지 위젯
  final Icon icon; // 페이지를 나타내는 아이콘

  /// **SecondaryInfo 생성자**
  /// - [title]: 페이지의 제목
  /// - [page]: 페이지를 렌더링할 위젯
  /// - [icon]: 페이지 아이콘
  SecondaryInfo(this.title, this.page, this.icon);
}

/// **Field Mode 페이지 목록**
final List<SecondaryInfo> fieldModePages = [
  SecondaryInfo('DashBoard', const DashBoard(), Icon(Icons.dashboard)),
  SecondaryInfo('Wireless', const Wireless(), Icon(Icons.wifi)),
  SecondaryInfo('Chat', const Chat(), Icon(Icons.message)),
  SecondaryInfo('DocuSign', const DocuSign(), Icon(Icons.document_scanner)),
];

/// **Office Mode 페이지 목록**
final List<SecondaryInfo> officeModePages = [
  SecondaryInfo('User Management', const UserManagement(), Icon(Icons.people)),
  SecondaryInfo('Location Management', const LocationManagement(), Icon(Icons.location_on)),
  SecondaryInfo('Adjustment', const Adjustment(), Icon(Icons.tune)),
  SecondaryInfo('Calendar', const Calander(), Icon(Icons.calendar_today)),
];
