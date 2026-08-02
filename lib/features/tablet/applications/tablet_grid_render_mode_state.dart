import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TabletGridRenderMode { twoD, threeD }

class TabletGridRenderModeState extends ChangeNotifier {
  static const String prefsKey = 'tablet_grid_render_mode_v1';

  TabletGridRenderMode _mode = TabletGridRenderMode.twoD;
  bool _isReady = false;
  Future<void> _persistQueue = Future<void>.value();

  TabletGridRenderModeState() {
    _restore();
  }

  TabletGridRenderMode get mode => _mode;
  bool get isReady => _isReady;
  bool get isTwoD => _mode == TabletGridRenderMode.twoD;
  bool get isThreeD => _mode == TabletGridRenderMode.threeD;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = (prefs.getString(prefsKey) ?? '').trim().toLowerCase();
      _mode = raw == '3d'
          ? TabletGridRenderMode.threeD
          : TabletGridRenderMode.twoD;
      debugPrint(
        '[TabletGridRenderMode] event=restored mode=${_mode.name}',
      );
    } catch (e) {
      _mode = TabletGridRenderMode.twoD;
      debugPrint(
        '[TabletGridRenderMode] event=restore_failed error=$e fallback=twoD',
      );
    } finally {
      _isReady = true;
      notifyListeners();
    }
  }

  Future<void> setMode(TabletGridRenderMode next) async {
    if (_mode == next && _isReady) return;
    final previous = _mode;
    _mode = next;
    notifyListeners();
    debugPrint(
      '[TabletGridRenderMode] event=changed from=${previous.name} to=${next.name}',
    );

    _persistQueue = _persistQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          prefsKey,
          next == TabletGridRenderMode.threeD ? '3d' : '2d',
        );
        debugPrint(
          '[TabletGridRenderMode] event=saved mode=${next.name}',
        );
      } catch (e) {
        debugPrint(
          '[TabletGridRenderMode] event=save_failed mode=${next.name} error=$e',
        );
      }
    });
    await _persistQueue;
  }

  Future<void> toggle() async {
    await setMode(
      _mode == TabletGridRenderMode.twoD
          ? TabletGridRenderMode.threeD
          : TabletGridRenderMode.twoD,
    );
  }
}
