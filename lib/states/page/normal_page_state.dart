import 'package:flutter/material.dart';

import '../../screens/normal_mode/normal_type_package/normal_parking_completed_page.dart';
import 'normal_page_info.dart';

class NormalPageState extends ChangeNotifier {
  final GlobalKey parkingCompletedKey;
  late final List<NormalPageInfo> pages;

  int selectedIndex = 0;

  /// UI 오버레이가 필요하면 외부(NormalPlateState)의 로딩을 보도록 권장.
  /// (여기 값은 기본 false 유지)
  bool isLoading = false;

  NormalPageState({List<NormalPageInfo>? pages}) : parkingCompletedKey = GlobalKey() {
    // 기본 페이지 구성(홈 1탭)
    this.pages = pages ?? buildNormalDefaultPages(parkingCompletedKey: parkingCompletedKey);
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
          NormalParkingCompletedPage.reset(parkingCompletedKey);
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
