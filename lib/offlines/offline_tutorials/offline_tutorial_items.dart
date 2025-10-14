// Enhanced: 카테고리 필드 + 설명(description) 필드로 변경
// Location: lib/offlines/tutorial/offline_tutorial_items.dart

class TutorialVideoItem {
  final String title;
  final String description; // ⬅ assetPath 대신 설명 필드 사용
  final String category; // 섹션 구분용

  const TutorialVideoItem({
    required this.title,
    required this.description,
    required this.category,
  });
}

/// 섹션(카테고리) 정렬 우선순위
class TutorialCategories {
  static const request = '요청';
  static const departure = '출차';
  static const parking = '주차';
  static const completed = '완료';
  static const etc = '기타';

  static const ordered = <String>[
    request,
    departure,
    parking,
    completed,
    etc,
  ];
}

/// 튜토리얼 목록.
/// 기존 assetPath 기반이 아니라, 사람 친화적인 설명(description)을 담습니다.
/// (영상 파일 경로나 로딩 방식은 별도 매핑 테이블/서비스에서 다루세요.)
class TutorialVideos {
  static const List<TutorialVideoItem> items = [
    TutorialVideoItem(
      title: "00 · 단순 입차 요청",
      description: "정산 선택",
      category: TutorialCategories.request,
    ),
    TutorialVideoItem(
      title: "01 · 상세 메모 입차 요청",
      description: "정산 선택, 메모 작성",
      category: TutorialCategories.request,
    ),
    TutorialVideoItem(
      title: "02 · 기존 메모 입차 요청",
      description: "메모 불러오기, 정산 선택",
      category: TutorialCategories.request,
    ),
    TutorialVideoItem(
      title: "03 · 정기 차량 입차 요청",
      description: "정기 주차,",
      category: TutorialCategories.request,
    ),
    TutorialVideoItem(
      title: "00 · 즉시 입차 완료",
      description: "정산 선택, 구역 선택",
      category: TutorialCategories.parking,
    ),
    TutorialVideoItem(
      title: "01 · 변경 입차 완료",
      description: "번호 선택, 구역 선택",
      category: TutorialCategories.parking,
    ),
    TutorialVideoItem(
      title: "00 · 변경 출차 요청",
      description: "번호 검색, 출차 요청",
      category: TutorialCategories.departure,
    ),
    TutorialVideoItem(
      title: "00 · 변경 출차 완료",
      description: "번호 선택, 출차 완료",
      category: TutorialCategories.departure,
    ),
    TutorialVideoItem(
      title: "00 · 로그 보기",
      description: "번호 선택, 로그 선택",
      category: TutorialCategories.etc,
    ),
  ];

  static TutorialVideoItem? byTitle(String title) {
    try {
      return items.firstWhere((e) => e.title == title);
    } catch (_) {
      return null;
    }
  }
}
