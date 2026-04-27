import 'package:shared_preferences/shared_preferences.dart';

const double kEdgeStripWidth = 32.0;

enum OverlayEdgeSide { left, right }

class OverlayEdgeSideConfig {
  static const String _prefsKey = 'overlay_edge_side';
  static const String _left = 'left';
  static const String _right = 'right';

  static Future<OverlayEdgeSide> getSide() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey) ?? _left;
    return raw == _right ? OverlayEdgeSide.right : OverlayEdgeSide.left;
  }

  static Future<void> setSide(OverlayEdgeSide side) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, side == OverlayEdgeSide.right ? _right : _left);
  }
}
