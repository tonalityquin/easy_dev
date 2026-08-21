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

  bool get usesLocation => false;
  bool get isCustomized => false;
  bool get isNewest => _timeOrder == RealTimeTimeOrder.newest;
  bool get isOldest => _timeOrder == RealTimeTimeOrder.oldest;
  bool get sortOldFirst => isOldest;
  RealTimePriorityMode get priorityMode => RealTimePriorityMode.sort;
  bool get isSortPriority => true;
  bool get isZonePriority => false;
  String get priorityLabel => '정렬';
  String get timeOrderLabel => isOldest ? '오래된순' : '최신순';
  String get selectedLocation => kRealTimeLocationAll;
  String get summaryLabel => '$priorityLabel · $timeOrderLabel';

  void setActiveTab({
    required String tabId,
    required String collection,
    required bool locationSupported,
  }) {
    final normalized = tabId.trim();
    final normalizedCollection = collection.trim();
    final changed = _activeTabId != normalized ||
        _activeCollection != normalizedCollection ||
        _locationSupported != locationSupported ||
        _mode != RealTimeSortMode.table;
    _activeTabId = normalized;
    _activeCollection = normalizedCollection;
    _locationSupported = locationSupported;
    if (_mode != RealTimeSortMode.table) {
      _mode = RealTimeSortMode.table;
      _revision += 1;
      debugPrint(
        '[RealTimePriority] normalized priority=sort mode=table reason=table_cell_only tab=$_activeTabId revision=$_revision',
      );
    }
    if (!changed) return;
    debugPrint(
      '[RealTimePriority] active_tab tab=$_activeTabId collection=${_activeCollection.isEmpty ? '-' : _activeCollection} tableMode=cell_only zoneButton=disabled order=$timeOrderLabel',
    );
    notifyListeners();
  }

  void togglePriority({String reason = 'user'}) {
    activateSortPriority(reason: 'zone_disabled:$reason');
    debugPrint(
      '[RealTimePriority] action=zone_toggle_ignored mode=table tableMode=cell_only zoneButton=disabled reason=$reason',
    );
  }

  void toggleTimeOrder({String reason = 'user'}) {
    final before = timeOrderLabel;
    _timeOrder = isNewest
        ? RealTimeTimeOrder.oldest
        : RealTimeTimeOrder.newest;
    _mode = RealTimeSortMode.table;
    _revision += 1;
    debugPrint(
      '[RealTimeSortOrder] action=toggle before=$before after=$timeOrderLabel field=createdAt priority=sort activeTab=${_activeTabId.isEmpty ? '-' : _activeTabId} reason=$reason revision=$_revision',
    );
    notifyListeners();
  }

  void activateSortPriority({String reason = 'user'}) {
    if (_mode == RealTimeSortMode.table) return;
    _mode = RealTimeSortMode.table;
    _revision += 1;
    debugPrint(
      '[RealTimePriority] apply priority=sort mode=table order=$timeOrderLabel activeTab=${_activeTabId.isEmpty ? '-' : _activeTabId} reason=$reason revision=$_revision',
    );
    notifyListeners();
  }

  void activateZonePriority({String reason = 'user'}) {
    activateSortPriority(reason: 'zone_disabled:$reason');
    debugPrint(
      '[RealTimePriority] action=zone_activation_ignored mode=table tableMode=cell_only zoneButton=disabled reason=$reason',
    );
  }

  void applyNewest({String reason = 'user'}) {
    final changed = !isNewest || _mode != RealTimeSortMode.table;
    _timeOrder = RealTimeTimeOrder.newest;
    _mode = RealTimeSortMode.table;
    if (!changed) return;
    _revision += 1;
    debugPrint(
      '[RealTimeSortOrder] action=apply_newest order=$timeOrderLabel priority=sort activeTab=${_activeTabId.isEmpty ? '-' : _activeTabId} reason=$reason revision=$_revision',
    );
    notifyListeners();
  }

  void applyAllZones({String reason = 'user'}) {
    activateSortPriority(reason: 'zone_disabled:$reason');
    debugPrint(
      '[RealTimePriority] action=all_zones_ignored mode=table tableMode=cell_only zoneButton=disabled reason=$reason',
    );
  }
}
