class TutorialVideoItem {
  final String title;
  final String description;
  final String category;
  final String assetPath;

  const TutorialVideoItem({
    required this.title,
    required this.description,
    required this.category,
    required this.assetPath,
  });
}

class TutorialCategories {
  static const request = '요청';
  static const parking = '주차';
  static const moveToParkingCompleted = '입차 완료';
  static const moveToDepartureRequest = '출차 요청';
  static const moveToDepartureCompleted = '출차 완료';
  static const etc = '기타';

  static const ordered = <String>[
    request,
    parking,
    moveToParkingCompleted,
    moveToDepartureRequest,
    moveToDepartureCompleted,
    etc,
  ];
}

class TutorialVideos {
  static const List<TutorialVideoItem> items = [
    TutorialVideoItem(
      title: "00 · 단순 입차 요청",
      description: "정산 선택",
      category: TutorialCategories.request,
      assetPath: "assets/tutorials/00request.mp4",
    ),
    TutorialVideoItem(
      title: "01 · 상세 메모 입차 요청",
      description: "정산 선택, 메모 작성",
      category: TutorialCategories.request,
      assetPath: "assets/tutorials/01request.mp4",
    ),
    TutorialVideoItem(
      title: "02 · 기존 메모 입차 요청",
      description: "메모 불러오기, 정산 선택",
      category: TutorialCategories.request,
      assetPath: "assets/tutorials/02request.mp4",
    ),
    TutorialVideoItem(
      title: "03 · 정기 차량 입차 요청",
      description: "정기 주차,",
      category: TutorialCategories.request,
      assetPath: "assets/tutorials/03request.mp4",
    ),
    TutorialVideoItem(
      title: "00 · 즉시 입차 완료",
      description: "정산 선택, 구역 선택",
      category: TutorialCategories.parking,
      assetPath: "assets/tutorials/00parkingcompleted.mp4",
    ),
    TutorialVideoItem(
      title: "01 · 변경 입차 완료",
      description: "번호 선택, 구역 선택",
      category: TutorialCategories.parking,
      assetPath: "assets/tutorials/00completed.mp4",
    ),
    TutorialVideoItem(
      title: "01 · 입차 완료로 이동",
      description: "번호 선택, 구역 선택",
      category: TutorialCategories.moveToParkingCompleted,
      assetPath: "assets/tutorials/0400moveToParkingCompleted.mp4",
    ),
    TutorialVideoItem(
      title: "01 · 출차 요청으로 이동",
      description: "번호 검색, 출차 요청",
      category: TutorialCategories.moveToDepartureRequest,
      assetPath: "assets/tutorials/0401moveToDepartureRequest.mp4",
    ),
    TutorialVideoItem(
      title: "01 · 출차 완료로 이동",
      description: "번호 선택, 출차 완료",
      category: TutorialCategories.moveToDepartureCompleted,
      assetPath: "assets/tutorials/0402moveToDepartureCompleted.mp4",
    ),
    TutorialVideoItem(
      title: "02 · 로그 보기",
      description: "번호 선택, 로그 선택",
      category: TutorialCategories.etc,
      assetPath: "assets/tutorials/00showlog.mp4",
    ),
  ];
}
