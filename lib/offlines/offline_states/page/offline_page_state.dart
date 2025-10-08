import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../screens/type_package/parking_completed_page.dart';
import '../../../states/plate/plate_state.dart';
import 'offline_page_info.dart';

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
        ParkingCompletedPage.reset(parkingCompletedKey);
        notifyListeners(); // 리셋 반영을 위해 리스너 알림
      }
      return; // 다른 탭은 기존대로 무시
    }

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

    // 홈 탭 최초/일반 진입 시 완료 페이지 상태 리셋
    if (index == 1) {
      ParkingCompletedPage.reset(parkingCompletedKey);
    }

    _selectedIndex = index;
    notifyListeners();
  }
}
