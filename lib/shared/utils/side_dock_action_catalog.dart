import 'package:flutter/material.dart';

class SideDockActionCatalog {
  static const String sectionReport = '보고';
  static const String sectionSubmit = '제출';
  static const String sectionForm = '양식';
  static const String sectionSupport = '지원';
  static const String sectionSettings = '설정';


  static const String faqLabel = 'FAQ';
  static const IconData faqIcon = Icons.help_center_rounded;

  static const String updateLabel = '업데이트';
  static const String updateDescription = '앱의 최신 업데이트를 확인합니다.';
  static const IconData updateIcon = Icons.system_update_alt_rounded;

  static const String themeDescription = '앱의 화면 테마를 변경합니다.';
  static const String workRulesDescription = '현재 지역의 업무 규칙을 확인합니다.';
  static const String workManualDescription = '현재 지역의 업무 메뉴얼을 확인합니다.';
  static const String monthlyParkingDescription =
      '정기 주차 차량 정보를 확인하고 관리합니다.';
  static const String departureCompletedDescription =
      '출차가 완료된 차량 내역을 확인합니다.';

  static const String termsLabel = '이용약관';
  static const IconData termsIcon = Icons.description_rounded;

  static const String privacyLabel = '개인정보보호처리방침';
  static const IconData privacyIcon = Icons.privacy_tip_rounded;

  static const String workStartReportLabel = '업무 시작 보고';
  static const String workStartReportDescription =
      '업무 시작 보고서를 작성합니다.';
  static const IconData workStartReportIcon = Icons.play_circle_outline_rounded;

  static const String workEndReportLabel = '업무 종료 보고';
  static const String workEndReportDescription =
      '업무 종료 보고서를 작성합니다.';
  static const IconData workEndReportIcon = Icons.task_alt_rounded;

  static const String commuteSubmitLabel = '출퇴근 기록 제출';
  static const String commuteSubmitDescription =
      '단말기의 출퇴근 기록을 서버에 제출합니다.';
  static const IconData commuteSubmitIcon = Icons.sync_alt_rounded;

  static const String restTimeSubmitLabel = '휴게시간 기록 제출';
  static const String restTimeSubmitDescription =
      '단말기의 휴게시간 기록을 서버에 제출합니다.';
  static const IconData restTimeSubmitIcon = Icons.free_breakfast_rounded;

  static const String statementFormLabel = '경위서 양식';
  static const String statementFormDescription =
      '경위서 작성 화면으로 이동합니다.';
  static const IconData statementFormIcon = Icons.description_rounded;

  static const String leaveApplicationLabel = '연차 지원 신청서';
  static const String leaveApplicationDescription =
      '연차·결근 지원 신청서를 작성합니다.';
  static const IconData leaveApplicationIcon = Icons.event_available_rounded;

  static const String operationsLabel = '운영 페이지 열기';
  static const String operationsDescription =
      '운영 관리 Side Dock을 엽니다.';
  static const IconData operationsIcon = Icons.open_in_new_rounded;

  static const String operationalSyncLabel = '지금 내려받기';
  static const String operationalSyncDescription =
      '현재 지역의 운영 데이터를 최신 상태로 내려받습니다.';
  static const IconData operationalSyncIcon = Icons.download_rounded;

  static const String logoutLabel = '로그아웃';
  static const String logoutDescription =
      '현재 계정에서 안전하게 로그아웃합니다.';
  static const IconData logoutIcon = Icons.logout_rounded;
}
