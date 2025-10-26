import 'package:flutter/material.dart';

import '../../offline_type_package/offline_parking_completed_page.dart';
import 'offline_page_info.dart';

class OfflinePageState with ChangeNotifier {
  final List<OfflinePageInfo> pages;

  final GlobalKey parkingCompletedKey = GlobalKey();

  int _selectedIndex;
  bool _isLoading = false;

  OfflinePageState({required this.pages})
      : assert(pages.isNotEmpty, "🚨 페이지 리스트가 비어 있습니다."),
        _selectedIndex = pages.length > 1 ? 1 : 0;

  int get selectedIndex => _selectedIndex;

  bool get isLoading => _isLoading;

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

    if (_selectedIndex == index) {
      if (index == 1) {
        OfflineParkingCompletedPage.reset(parkingCompletedKey);
        notifyListeners();
      }
      return;
    }

    if (index == 1) {
      OfflineParkingCompletedPage.reset(parkingCompletedKey);
    }

    _selectedIndex = index;
    notifyListeners();
  }
}
