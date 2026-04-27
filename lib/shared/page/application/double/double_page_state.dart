import 'package:flutter/material.dart';

import 'double_page_info.dart';

class DoublePageState extends ChangeNotifier {
  final GlobalKey parkingCompletedKey;
  late final List<DoublePageInfo> pages;

  int selectedIndex = 0;

  
  
  bool isLoading = false;

  DoublePageState({List<DoublePageInfo>? pages}) : parkingCompletedKey = GlobalKey() {
    
    this.pages = pages ?? buildDoubleDefaultPages(parkingCompletedKey: parkingCompletedKey);
  }

  Future<void> onItemTapped(
      BuildContext context,
      int index, {
        required void Function(String) onError,
      }) async {
    try {
      if (index == selectedIndex) {
        if (index == 0) {
          debugPrint('[DoublePageState] home retap (table-only) — no action');
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
