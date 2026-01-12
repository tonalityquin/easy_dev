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

  // ✅ [추가] 출차 요청 aggregation count 갱신 트리거 토큰
  int departureRequestsCountRefreshToken = 0;

  // ✅ [추가] 홈 연타/과도 호출 방지용 쿨다운(Throttle)
  static const Duration _departureCountCooldown = Duration(milliseconds: 800);
  DateTime? _lastDepartureCountBumpAt;

  NormalPageState({List<NormalPageInfo>? pages}) : parkingCompletedKey = GlobalKey() {
    // 기본 페이지 구성(홈 1탭)
    this.pages = pages ?? buildNormalDefaultPages(parkingCompletedKey: parkingCompletedKey);
  }

  /// ✅ [추가] 같은 area에서도 count().get()을 다시 호출시키기 위한 bump
  /// - 0.8초 내 연속 호출은 무시(쿨다운)
  /// - 성공적으로 bump되면 notifyListeners()로 UI에 refreshToken 변경을 전파
  bool bumpDepartureRequestsCountRefreshToken() {
    final now = DateTime.now();
    final last = _lastDepartureCountBumpAt;

    if (last != null && now.difference(last) < _departureCountCooldown) {
      return false; // 쿨다운 중: 무시
    }

    _lastDepartureCountBumpAt = now;
    departureRequestsCountRefreshToken++;
    notifyListeners();
    return true;
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
