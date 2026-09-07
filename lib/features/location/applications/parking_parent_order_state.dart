import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParkingParentOrderState extends ChangeNotifier {
  static const String prefsKey = 'parking_parent_order_v1';

  final Map<String, List<String>> _ordersByArea = <String, List<String>>{};
  Future<void> _persistQueue = Future<void>.value();
  late final Future<void> _restoreFuture;
  bool _isReady = false;

  ParkingParentOrderState() {
    _restoreFuture = _restore();
  }

  bool get isReady => _isReady;

  static String normalizeName(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String canonicalKey(String raw) {
    return normalizeName(raw).toLowerCase();
  }

  String _areaKey(String area) => canonicalKey(area);

  bool hasCustomOrder(String area) {
    final order = _ordersByArea[_areaKey(area)];
    return order != null && order.isNotEmpty;
  }

  List<String> storedOrderForArea(String area) {
    return List<String>.unmodifiable(
      _ordersByArea[_areaKey(area)] ?? const <String>[],
    );
  }

  Map<String, int> rankMapForArea(String area) {
    final order = _ordersByArea[_areaKey(area)] ?? const <String>[];
    return <String, int>{
      for (var index = 0; index < order.length; index++) order[index]: index,
    };
  }

  Comparator<String> comparatorForArea(
    String area, {
    Comparator<String>? fallback,
  }) {
    final ranks = rankMapForArea(area);
    return (left, right) {
      final leftKey = canonicalKey(left);
      final rightKey = canonicalKey(right);
      final leftRank = ranks[leftKey];
      final rightRank = ranks[rightKey];
      if (leftRank != null && rightRank != null) {
        final rankCompare = leftRank.compareTo(rightRank);
        if (rankCompare != 0) return rankCompare;
      } else if (leftRank != null) {
        return -1;
      } else if (rightRank != null) {
        return 1;
      }
      final fallbackCompare = fallback?.call(left, right) ??
          normalizeName(left)
              .toLowerCase()
              .compareTo(normalizeName(right).toLowerCase());
      if (fallbackCompare != 0) return fallbackCompare;
      return normalizeName(left).compareTo(normalizeName(right));
    };
  }

  List<String> resolveNames(
    String area,
    Iterable<String> available, {
    Comparator<String>? fallback,
  }) {
    final byKey = <String, String>{};
    for (final raw in available) {
      final display = raw.trim();
      final key = canonicalKey(display);
      if (key.isEmpty) continue;
      byKey.putIfAbsent(key, () => display);
    }
    final resolved = byKey.values.toList(growable: false);
    resolved.sort(comparatorForArea(area, fallback: fallback));
    return resolved;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = (prefs.getString(prefsKey) ?? '').trim();
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final areaKey = canonicalKey(entry.key.toString());
            if (areaKey.isEmpty || entry.value is! List) continue;
            final seen = <String>{};
            final order = <String>[];
            for (final value in entry.value as List) {
              final key = canonicalKey(value.toString());
              if (key.isEmpty || !seen.add(key)) continue;
              order.add(key);
            }
            if (order.isNotEmpty) {
              _ordersByArea[areaKey] = List<String>.unmodifiable(order);
            }
          }
        }
      }
      debugPrint(
        '[ParkingParentOrder] event=restored areaCount=${_ordersByArea.length} storage=$prefsKey',
      );
    } catch (error) {
      _ordersByArea.clear();
      debugPrint(
        '[ParkingParentOrder] event=restore_failed error=$error fallback=natural_sort',
      );
    } finally {
      _isReady = true;
      notifyListeners();
    }
  }

  Future<bool> setOrder(String area, Iterable<String> parentNames) async {
    await _restoreFuture;
    final areaKey = _areaKey(area);
    if (areaKey.isEmpty) {
      debugPrint('[ParkingParentOrder] event=save_rejected reason=empty_area');
      return false;
    }
    final seen = <String>{};
    final nextOrder = <String>[];
    for (final raw in parentNames) {
      final key = canonicalKey(raw);
      if (key.isEmpty || !seen.add(key)) continue;
      nextOrder.add(key);
    }
    if (nextOrder.isEmpty) {
      debugPrint(
        '[ParkingParentOrder] event=save_rejected area=$area reason=empty_order',
      );
      return false;
    }
    final previous = _ordersByArea[areaKey] ?? const <String>[];
    if (listEquals(previous, nextOrder)) {
      debugPrint(
        '[ParkingParentOrder] event=save_skipped area=$area reason=unchanged count=${nextOrder.length}',
      );
      return true;
    }
    final snapshot = <String, List<String>>{
      for (final entry in _ordersByArea.entries)
        entry.key: List<String>.of(entry.value),
      areaKey: List<String>.of(nextOrder),
    };
    var success = false;
    _persistQueue = _persistQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final encoded = jsonEncode(snapshot);
        final saved = await prefs.setString(prefsKey, encoded);
        if (!saved) {
          debugPrint(
            '[ParkingParentOrder] event=save_failed area=$area reason=shared_preferences_false count=${nextOrder.length}',
          );
          return;
        }
        _ordersByArea
          ..clear()
          ..addAll(
            <String, List<String>>{
              for (final entry in snapshot.entries)
                entry.key: List<String>.unmodifiable(entry.value),
            },
          );
        success = true;
        debugPrint(
          '[ParkingParentOrder] event=saved area=$area count=${nextOrder.length} order=${nextOrder.join(">")}',
        );
        notifyListeners();
      } catch (error) {
        debugPrint(
          '[ParkingParentOrder] event=save_failed area=$area error=$error count=${nextOrder.length}',
        );
      }
    });
    await _persistQueue;
    return success;
  }
}
