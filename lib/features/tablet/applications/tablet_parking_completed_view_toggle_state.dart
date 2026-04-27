import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TabletParkingCompletedViewToggleState extends ChangeNotifier {
  static const String prefsKey =
      'tablet_include_parking_completed_view_subscription';

  bool _includeParkingCompletedView = false;
  bool _isReady = false;

  TabletParkingCompletedViewToggleState() {
    _restore();
  }

  bool get includeParkingCompletedView => _includeParkingCompletedView;
  bool get isReady => _isReady;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _includeParkingCompletedView = prefs.getBool(prefsKey) ?? false;
    } catch (e) {
      debugPrint('TabletParkingCompletedViewToggleState restore failed: $e');
      _includeParkingCompletedView = false;
    } finally {
      _isReady = true;
      notifyListeners();
    }
  }

  Future<void> setIncludeParkingCompletedView(bool next) async {
    if (_includeParkingCompletedView == next && _isReady) return;
    _includeParkingCompletedView = next;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, next);
    } catch (e) {
      debugPrint('TabletParkingCompletedViewToggleState save failed: $e');
    }
  }

  Future<void> toggle() async {
    await setIncludeParkingCompletedView(!_includeParkingCompletedView);
  }
}
