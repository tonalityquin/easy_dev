import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/type_pages/parking_completed_page.dart';
import 'page_info.dart';
import '../../states/plate/plate_state.dart';
import '../../enums/plate_type.dart';

class PageState with ChangeNotifier {
  final List<PageInfo> pages;

  /// ✅ ParkingCompletedPage 전용 GlobalKey
  final GlobalKey parkingCompletedKey = GlobalKey();

  int _selectedIndex;
  bool _isLoading = false;

  PageState({required this.pages})
      : _selectedIndex = pages.isNotEmpty
      ? 1
      : throw Exception("🚨 페이지 리스트가 비어 있습니다.");

  int get selectedIndex => _selectedIndex;
  bool get isLoading => _isLoading;
  String get selectedPageTitle => pages[_selectedIndex].title;

  set isLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      notifyListeners();
    }
  }

  /// ✅ 탭 전환 처리
  void onItemTapped(
      BuildContext context,
      int index, {
        void Function(String)? onError,
      }) {
    if (index < 0 || index >= pages.length) {
      final error = '🚨 Invalid index: $index';
      debugPrint(error);
      return;
    }

    final plateState = context.read<PlateState>();

    // ✅ 입차 요청 탭일 때 데이터 유무 확인
    if (index == 0) {
      final plates =
      plateState.getPlatesByCollection(PlateType.parkingRequests);
      if (plates.isEmpty) {
        debugPrint("🚫 입차 요청 데이터가 없습니다.");
        return;
      }
    }

    // ✅ 출차 요청 탭일 때 데이터 유무 확인
    if (index == 2) {
      final plates =
      plateState.getPlatesByCollection(PlateType.departureRequests);
      if (plates.isEmpty) {
        debugPrint("🚫 출차 요청 데이터가 없습니다.");
        return;
      }
    }

    // ✅ 입차 완료 탭일 경우 ParkingCompletedPage 상태 초기화
    if (index == 1) {
      ParkingCompletedPage.reset(parkingCompletedKey);
    }

    _selectedIndex = index;
    notifyListeners();
  }
}
