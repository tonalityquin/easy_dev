import 'package:flutter/material.dart';
import '../screens/secondary_pages/dash_board.dart'; // 대시보드 페이지
import '../screens/secondary_pages/docu_sign.dart'; // 관리 페이지
import '../screens/secondary_pages/chat.dart'; // 채팅 페이지
import '../screens/secondary_pages/wireless.dart'; // 무전 페이지

/// **SecondaryInfo 클래스**
/// - 화면 정보를 저장하는 데이터 클래스
/// - 각 화면의 타이틀, 페이지 위젯, 아이콘을 포함
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

/// **기본 페이지 목록 정의**
/// - 앱에서 사용되는 각 페이지의 정보를 포함
final List<SecondaryInfo> defaultPages = [
  // 대시보드 페이지
  SecondaryInfo(
    'DashBoard', // 타이틀
    const DashBoard(), // 위젯
    Icon(Icons.dashboard), // 아이콘
  ),

  // 무전 페이지
  SecondaryInfo(
    'Wireless', // 타이틀
    const Wireless(), // 위젯
    Icon(Icons.wifi), // 아이콘
  ),

  // 채팅 페이지
  SecondaryInfo(
    'Chat', // 타이틀
    const Chat(), // 위젯
    Icon(Icons.message), // 아이콘
  ),

  // 전자사인 페이지
  SecondaryInfo(
    'DocuSign', // 타이틀
    const DocuSign(), // 위젯
    Icon(Icons.document_scanner), // 아이콘
  ),
];
