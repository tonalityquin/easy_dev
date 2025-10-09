import 'package:flutter/material.dart';

import '../../offline_type_package/offline_parking_completed_page.dart';
import 'offline_page_info.dart';

/// 탭 이동 시 '데이터 유무로 이동 차단' 로직을 제거하여
/// 입차 요청/출차 요청 화면은 데이터가 없더라도 항상 진입 가능하게 함.
class OfflinePageState with ChangeNotifier {
  final List<OfflinePageInfo> pages;

  /// 홈(완료) 탭의 상태 초기화를 위해 사용하는 GlobalKey
  final GlobalKey parkingCompletedKey = GlobalKey();

  int _selectedIndex;
  bool _isLoading = false;

  /// 기본 선택 탭을 '홈'(index 1)로 설정하되,
  /// 페이지가 1개뿐이면 0으로 안전하게 시작
  OfflinePageState({required this.pages})
      : assert(pages.isNotEmpty, "🚨 페이지 리스트가 비어 있습니다."),
        _selectedIndex = pages.length > 1 ? 1 : 0;

  int get selectedIndex => _selectedIndex;

  bool get isLoading => _isLoading;

  String get selectedPageTitle => pages[_selectedIndex].title;

  set isLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      notifyListeners();
    }
  }

  void onItemTapped(
      BuildContext context,
      int index, {
        void Function(String)? onError,
      }) {
    // 인덱스 범위 체크
    if (index < 0 || index >= pages.length) {
      final error = '🚨 Invalid index: $index';
      debugPrint(error);
      onError?.call(error);
      return;
    }

    // ✅ 같은 탭 재선택 처리
    // - 홈(인덱스 1) 재탭 시 ParkingCompletedPage를 리셋하여
    //   ParkingStatusPage부터 다시 시작하고, 화면 잠금(isLocked)을 true로 설정
    if (_selectedIndex == index) {
      if (index == 1) {
        OfflineParkingCompletedPage.reset(parkingCompletedKey);
        notifyListeners(); // 리셋 반영을 위해 리스너 알림
      }
      return;
    }

    // ❌ (삭제됨) 데이터 유무로 탭 이동 차단 로직
    //    - 입차 요청/출차 요청 데이터가 없어도 화면 진입 가능해야 하므로 제거

    // 홈 탭 최초/일반 진입 시 완료 페이지 상태 리셋
    if (index == 1) {
      OfflineParkingCompletedPage.reset(parkingCompletedKey);
    }

    _selectedIndex = index;
    notifyListeners();
  }
}
