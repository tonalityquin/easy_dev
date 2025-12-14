import 'package:flutter/material.dart';

import '../../screens/service_mode/type_package/parking_completed_page.dart';
import 'lite_page_info.dart';

class LitePageState with ChangeNotifier {
  final List<LitePageInfo> pages;

  /// 홈(완료) 상태 리셋용
  final GlobalKey parkingCompletedKey = GlobalKey();

  int _selectedIndex;
  bool _isLoading = false;

  /// ✅ 홈 1탭이면 0부터 시작
  LitePageState({required this.pages})
      : assert(pages.isNotEmpty, "🚨 페이지 리스트가 비어 있습니다."),
        _selectedIndex = 0;

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
    if (index < 0 || index >= pages.length) {
      final error = '🚨 Invalid index: $index';
      debugPrint(error);
      onError?.call(error);
      return;
    }

    // ✅ 같은 탭(홈) 재탭 시: ParkingCompletedPage 리셋
    if (_selectedIndex == index) {
      ParkingCompletedPage.reset(parkingCompletedKey);
      notifyListeners();
      return;
    }

    _selectedIndex = index;

    // (확장 대비) 홈 진입 시 리셋 유지
    if (pages[index].title == '홈') {
      ParkingCompletedPage.reset(parkingCompletedKey);
    }

    notifyListeners();
  }
}
