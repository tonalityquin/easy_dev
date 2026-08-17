import 'package:flutter/foundation.dart';

import 'real_time_table_zone.dart';

class RealTimeChildFocusBackGuard {
  static Object? _owner;
  static VoidCallback? _handler;

  static bool get hasHandler => _handler != null;

  static void register(Object owner, VoidCallback handler) {
    _owner = owner;
    _handler = handler;
  }

  static void unregister(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _handler = null;
  }

  static bool handleBack() {
    final handler = _handler;
    if (handler == null) return false;
    handler();
    return true;
  }
}

enum RealTimeSortMode {
  table,
  locationParent,
}

enum RealTimePriorityMode {
  sort,
  zone,
}

enum RealTimeTimeOrder {
  newest,
  oldest,
}

class RealTimeSortState extends ChangeNotifier {
  RealTimeSortMode _mode = RealTimeSortMode.table;
  RealTimeTimeOrder _timeOrder = RealTimeTimeOrder.newest;
  String _activeTabId = '';
  String _activeCollection = '';
  bool _locationSupported = true;
  int _revision = 0;

  RealTimeSortMode get mode => _mode;
  RealTimeTimeOrder get timeOrder => _timeOrder;
  String get parent => '';
  String get child => '';
  String get activeTabId => _activeTabId;
  String get activeCollection => _activeCollection;
  bool get locationSupported => _locationSupported;
  int get revision => _revision;

  bool get usesLocation => _mode == RealTimeSortMode.locationParent;
  bool get isCustomized => usesLocation;
  bool get isNewest => _timeOrder == RealTimeTimeOrder.newest;
  bool get isOldest => _timeOrder == RealTimeTimeOrder.oldest;
  bool get sortOldFirst => isOldest;
  RealTimePriorityMode get priorityMode =>
      usesLocation ? RealTimePriorityMode.zone : RealTimePriorityMode.sort;
  bool get isSortPriority => priorityMode == RealTimePriorityMode.sort;
  bool get isZonePriority => priorityMode == RealTimePriorityMode.zone;
  String get priorityLabel => isZonePriority ? '구역' : '정렬';
  String get timeOrderLabel => isOldest ? '오래된순' : '최신순';
  String get selectedLocation => kRealTimeLocationAll;
  String get summaryLabel => isZonePriority
      ? '$priorityLabel · 부모 구역'
      : '$priorityLabel · $timeOrderLabel';

  void setActiveTab({
    required String tabId,
    required String collection,
    required bool locationSupported,
  }) {
    final normalized = tabId.trim();
    final normalizedCollection = collection.trim();
    final changed = _activeTabId != normalized ||
        _activeCollection != normalizedCollection ||
        _locationSupported != locationSupported;
    _activeTabId = normalized;
    _activeCollection = normalizedCollection;
    _locationSupported = locationSupported;
    if (!_locationSupported && usesLocation) {
      _mode = RealTimeSortMode.table;
      _revision += 1;
      debugPrint(
        '[RealTimePriority] normalized priority=sort order=$timeOrderLabel reason=active_tab_zone_unsupported tab=$_activeTabId revision=$_revision',
      );
      notifyListeners();
      return;
    }
    if (!changed) return;
    debugPrint(
      '[RealTimePriority] active_tab tab=$_activeTabId collection=${_activeCollection.isEmpty ? '-' : _activeCollection} zoneSupported=$_locationSupported priority=${priorityMode.name} order=$timeOrderLabel',
    );
    notifyListeners();
  }

  void togglePriority({String reason = 'user'}) {
    if (isZonePriority) {
      activateSortPriority(reason: reason);
    } else {
      activateZonePriority(reason: reason);
    }
  }

  void toggleTimeOrder({String reason = 'user'}) {
    final before = timeOrderLabel;
    _timeOrder = isNewest
        ? RealTimeTimeOrder.oldest
        : RealTimeTimeOrder.newest;
    _revision += 1;
    debugPrint(
      '[RealTimeSortOrder] action=toggle before=$before after=$timeOrderLabel field=createdAt priority=${priorityMode.name} activeTab=${_activeTabId.isEmpty ? '-' : _activeTabId} reason=$reason revision=$_revision',
    );
    notifyListeners();
  }

  void activateSortPriority({String reason = 'user'}) {
    _apply(mode: RealTimeSortMode.table, reason: reason);
  }

  void activateZonePriority({String reason = 'user'}) {
    if (!_locationSupported) {
      activateSortPriority(reason: 'zone_unsupported');
      return;
    }
    _apply(mode: RealTimeSortMode.locationParent, reason: reason);
  }

  void applyNewest({String reason = 'user'}) {
    final changed = !isNewest;
    _timeOrder = RealTimeTimeOrder.newest;
    final modeChanged = _mode != RealTimeSortMode.table;
    _mode = RealTimeSortMode.table;
    if (!changed && !modeChanged) return;
    _revision += 1;
    debugPrint(
      '[RealTimeSortOrder] action=apply_newest order=$timeOrderLabel priority=${priorityMode.name} activeTab=${_activeTabId.isEmpty ? '-' : _activeTabId} reason=$reason revision=$_revision',
    );
    notifyListeners();
  }

  void applyAllZones({String reason = 'user'}) {
    activateZonePriority(reason: reason);
  }

  void _apply({
    required RealTimeSortMode mode,
    required String reason,
  }) {
    if (_mode == mode) return;
    _mode = mode;
    _revision += 1;
    debugPrint(
      '[RealTimePriority] apply priority=${priorityMode.name} mode=${_mode.name} order=$timeOrderLabel selectedLocation=$selectedLocation activeTab=${_activeTabId.isEmpty ? '-' : _activeTabId} collection=${_activeCollection.isEmpty ? '-' : _activeCollection} zoneSupported=$_locationSupported reason=$reason revision=$_revision',
    );
    notifyListeners();
  }
}
