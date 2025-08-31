// lib/states/page/page_state.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/type_pages/parking_completed_page.dart';
import 'page_info.dart';
import '../../states/plate/plate_state.dart';
import '../../enums/plate_type.dart';

class PageState with ChangeNotifier {
  final List<PageInfo> pages;

  /// 홈(완료) 탭의 상태 초기화를 위해 사용하는 GlobalKey
  final GlobalKey parkingCompletedKey = GlobalKey();

  int _selectedIndex;
  bool _isLoading = false;

  /// 기본 선택 탭을 '홈'(index 1)로 설정하되,
  /// 페이지가 1개뿐이면 0으로 안전하게 시작
  PageState({required this.pages})
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

    // 같은 탭 재선택이면 아무 작업도 하지 않음(불필요한 rebuild 방지)
    if (_selectedIndex == index) return;

    final plateState = context.read<PlateState>();

    // 입차 요청 탭: 데이터 없으면 이동 막기
    if (index == 0) {
      final plates = plateState.getPlatesByCollection(PlateType.parkingRequests);
      if (plates.isEmpty) {
        const msg = "🚫 입차 요청 데이터가 없습니다.";
        debugPrint(msg);
        onError?.call(msg);
        return;
      }
    }

    // 출차 요청 탭: 데이터 없으면 이동 막기
    if (index == 2) {
      final plates = plateState.getPlatesByCollection(PlateType.departureRequests);
      if (plates.isEmpty) {
        const msg = "🚫 출차 요청 데이터가 없습니다.";
        debugPrint(msg);
        onError?.call(msg);
        return;
      }
    }

    // 홈 탭 진입 시 완료 페이지 상태 리셋
    if (index == 1) {
      ParkingCompletedPage.reset(parkingCompletedKey);
    }

    _selectedIndex = index;
    notifyListeners();
  }
}
