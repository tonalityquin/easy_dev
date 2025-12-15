import 'package:flutter/material.dart';

import '../../screens/lite_mode/lite_type_package/lite_parking_completed_page.dart';
import 'lite_page_info.dart';

class LitePageState extends ChangeNotifier {
  final GlobalKey parkingCompletedKey;
  late final List<LitePageInfo> pages;

  int selectedIndex = 0;

  /// UI 오버레이가 필요하면 외부(LitePlateState)의 로딩을 보도록 권장.
  /// (여기 값은 기본 false 유지)
  bool isLoading = false;

  LitePageState({List<LitePageInfo>? pages}) : parkingCompletedKey = GlobalKey() {
    // 기본 페이지 구성(홈 1탭)
    this.pages = pages ?? buildLiteDefaultPages(parkingCompletedKey: parkingCompletedKey);
  }

  Future<void> onItemTapped(
      BuildContext context,
      int index, {
        required void Function(String) onError,
      }) async {
    try {
      // 홈 1탭 구성: 재탭이면 reset
      if (index == selectedIndex) {
        if (index == 0) {
          LiteParkingCompletedPage.reset(parkingCompletedKey);
        }
        return;
      }

      selectedIndex = index;
      notifyListeners();
    } catch (e) {
      onError('페이지 이동 처리 중 오류: $e');
    }
  }
}
