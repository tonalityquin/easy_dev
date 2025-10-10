// Enhanced: 카테고리 필드 추가
// Location: lib/offlines/tutorial/offline_tutorial_items.dart

class TutorialVideoItem {
  final String title;
  final String assetPath;
  final String category; // 섹션 구분용

  const TutorialVideoItem({
    required this.title,
    required this.assetPath,
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

/// 튜토리얼 비디오 목록 (assets 기반).
/// pubspec.yaml 에 assets/tutorials/ 가 등록되어 있어야 합니다.
class TutorialVideos {
  static const List<TutorialVideoItem> items = [
    TutorialVideoItem(
      title: "00 · 완료",
      assetPath: "assets/tutorials/00completed.mp4",
      category: TutorialCategories.completed,
    ),
    TutorialVideoItem(
      title: "00 · 출차 완료",
      assetPath: "assets/tutorials/00departurecompleted.mp4",
      category: TutorialCategories.departure,
    ),
    TutorialVideoItem(
      title: "00 · 출차 요청",
      assetPath: "assets/tutorials/00departurerequest.mp4",
      category: TutorialCategories.departure,
    ),
    TutorialVideoItem(
      title: "00 · 주차 완료",
      assetPath: "assets/tutorials/00parkingcompleted.mp4",
      category: TutorialCategories.parking,
    ),
    TutorialVideoItem(
      title: "00 · 요청",
      assetPath: "assets/tutorials/00request.mp4",
      category: TutorialCategories.request,
    ),
    TutorialVideoItem(
      title: "00 · 로그 보기",
      assetPath: "assets/tutorials/00showlog.mp4",
      category: TutorialCategories.etc,
    ),
    TutorialVideoItem(
      title: "01 · 요청",
      assetPath: "assets/tutorials/01request.mp4",
      category: TutorialCategories.request,
    ),
    TutorialVideoItem(
      title: "02 · 요청",
      assetPath: "assets/tutorials/02request.mp4",
      category: TutorialCategories.request,
    ),
    TutorialVideoItem(
      title: "03 · 요청",
      assetPath: "assets/tutorials/03request.mp4",
      category: TutorialCategories.request,
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
