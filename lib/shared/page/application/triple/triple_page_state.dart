import 'package:flutter/material.dart';

import 'triple_page_info.dart';

class TriplePageState extends ChangeNotifier {
  final GlobalKey parkingCompletedKey;
  late final List<TriplePageInfo> pages;

  int selectedIndex = 0;

  
  
  bool isLoading = false;

  
  int departureRequestsCountRefreshToken = 0;

  
  static const Duration _departureCountCooldown = Duration(milliseconds: 800);
  DateTime? _lastDepartureCountBumpAt;

  TriplePageState({List<TriplePageInfo>? pages}) : parkingCompletedKey = GlobalKey() {
    
    this.pages = pages ?? buildTripleDefaultPages(parkingCompletedKey: parkingCompletedKey);
  }

  
  
  
  bool bumpDepartureRequestsCountRefreshToken() {
    final now = DateTime.now();
    final last = _lastDepartureCountBumpAt;

    if (last != null && now.difference(last) < _departureCountCooldown) {
      return false; 
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
      
      if (index == selectedIndex) {
        if (index == 0) {
          debugPrint('[TriplePageState] home retap (table-only) — no action');
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
