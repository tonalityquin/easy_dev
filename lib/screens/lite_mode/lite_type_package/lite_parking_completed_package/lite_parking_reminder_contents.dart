// lib/screens/type_package/parking_completed_package/parking_reminder_contents.dart

/// 주차 현황 페이지 하단에 노출되는
/// 중앙 정렬 업무 리마인더 카드 콘텐츠 정의 파일.
///
/// - UI 위젯 코드와 분리하여 텍스트만 별도 관리
/// - [parkingRemindersForArea] 를 통해 지역별 콘텐츠 제공
class LiteParkingReminderContents {
  final String title;
  final List<String> lines;

  const LiteParkingReminderContents({
    required this.title,
    required this.lines,
  });
}

const List<LiteParkingReminderContents> kDefaultParkingReminderContents = [
  LiteParkingReminderContents(
    title: 'Test Title',
    lines: [
      '• Test line 1',
      '• Test line 2',
    ],
  ),
];

final Map<String, List<LiteParkingReminderContents>> kParkingReminderContentsByArea = {
  '가로수길(캔버스랩)': [
    const LiteParkingReminderContents(
      title: '업무 시작 전',
      lines: [
        '• 근무지 청소 후, 업무 시작 준비하기',
        '• 지급 받은 유니폼 환복 후, 근무지 이상 유무 확인 후 보고하기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '업무 중',
      lines: [
        '• 유튜브 시청, 라디오 청취 중 비업무 요소와 거리두기',
        '• 흡연 등을 이유로 보고 없이 근무지 벗어나지 않기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '사고 발생 시',
      lines: [
        '• 현장 및 지정 관리자에게 보고하기',
        '• 관리자의 메뉴얼을 절대 준수하기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '고객 응대 시',
      lines: [
        '• 지정 관리자로부터 교육 받은 업무 외 임의의 서비스 제공하지 않기',
        '• 내방객과 담소, 반말 등 절대 하지 않기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '컴플레인 발생 시',
      lines: [
        '• 컴플레인 당사자와의 다툼은 절대 피하기',
        '• 현장 관리자를 통해서 컴플레인 해결하기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '업무 인수 인계 시',
      lines: [
        '• 상호 대면을 한 환경에서 업무 인수 인계 진행하기',
        '• 마감조는 반드시 오픈조로부터 직접 업무 인수 인계를 받기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '업무 종료 시',
      lines: [
        '• 휴게 및 퇴근 보고는 반드시 하기',
        '• 제공된 유니폼 정돈 및 청결하게 관리하기',
      ],
    ),
  ],
  '북한강막국수닭갈비': [
    const LiteParkingReminderContents(
      title: '업무 시작 전',
      lines: [
        '• 근무지 청소 후, 업무 시작 준비하기',
        '• 지급 받은 유니폼 환복 후, 근무지 이상 유무 확인 후 보고하기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '업무 중',
      lines: [
        '• 유튜브 시청, 라디오 청취 중 비업무 요소와 거리두기',
        '• 흡연 등을 이유로 보고 없이 근무지 벗어나지 않기',
        '• 자전거 도로 및 중앙선 침범 차량 유의하여 조심하기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '사고 발생 시',
      lines: [
        '• 현장 및 지정 관리자에게 보고하기',
        '• 관리자의 메뉴얼을 절대 준수하기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '고객 응대 시',
      lines: [
        '• 지정 관리자로부터 교육 받은 업무 외 임의의 서비스 제공하지 않기',
        '• 내방객과 담소, 반말 등 절대 하지 않기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '컴플레인 발생 시',
      lines: [
        '• 컴플레인 당사자와의 다툼은 절대 피하기',
        '• 현장 관리자를 통해서 컴플레인 해결하기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '업무 인수 인계 시',
      lines: [
        '• 상호 대면을 한 환경에서 업무 인수 인계 진행하기',
        '• 마감조는 반드시 오픈조로부터 직접 업무 인수 인계를 받기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '업무 종료 시',
      lines: [
        '• 휴게 및 퇴근 보고는 반드시 하기',
        '• 제공된 유니폼 정돈 및 청결하게 관리하기',
      ],
    ),
  ],
  'britishArea': [
    const LiteParkingReminderContents(
      title: '브리티시 존 주의사항',
      lines: [
        '• 외국인 고객이 많으니 영어 안내 문구를 미리 숙지하기',
        '• 차량 출입 시 좌우 교행에 특히 유의하기',
      ],
    ),
    const LiteParkingReminderContents(
      title: '브리티시 존 업무 팁',
      lines: [
        '• 고객이 찾기 쉬운 기준 지점을 한두 개 기억해 두기',
        '• 반복 문의가 많은 안내는 메모해 두고 활용하기',
      ],
    ),
  ],
  'engArea': [
    const LiteParkingReminderContents(
      title: 'ENG Area 안내',
      lines: [
        '• 영어로 기본 인사와 간단한 안내를 시도해 보기',
        '• 이해가 어려우면 즉시 관리자에게 도움 요청하기',
      ],
    ),
    const LiteParkingReminderContents(
      title: 'ENG Area 업무 유의사항',
      lines: [
        '• 안내 표지판의 영어 문구가 잘 보이는지 수시로 확인하기',
        '• 외국인 고객 응대 시 느리게 또박또박 말하기',
      ],
    ),
  ],
};

/// 주어진 area 문자열에 대해 사용할 리마인더 목록을 반환
List<LiteParkingReminderContents> parkingRemindersForArea(String area) {
  final key = area.trim();
  final list = kParkingReminderContentsByArea[key];
  if (list != null) {
    return list;
  }

  return kDefaultParkingReminderContents;
}

/// (선택) 이전 코드와의 호환성을 위해 남겨둔 상수.
/// 현재는 "기본(공통) 리마인더" 를 가리킵니다.
const List<LiteParkingReminderContents> kParkingReminderContents = kDefaultParkingReminderContents;
