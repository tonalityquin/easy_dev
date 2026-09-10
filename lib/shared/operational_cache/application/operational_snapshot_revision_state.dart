import 'dart:async';

import 'package:flutter/foundation.dart';

class OperationalSnapshotRevisionState extends ChangeNotifier {
  final Map<String, int> _revisionByArea = <String, int>{};
  final Map<String, void Function(String)> _logByArea =
      <String, void Function(String)>{};
  final Map<String, Timer> _logExpiryByArea = <String, Timer>{};

  int revisionOf(String area) {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) return 0;
    return _revisionByArea[normalizedArea] ?? 0;
  }

  int markSynced(
    String area, {
    void Function(String)? onLog,
  }) {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) return 0;

    final nextRevision = (_revisionByArea[normalizedArea] ?? 0) + 1;
    _revisionByArea[normalizedArea] = nextRevision;

    _logExpiryByArea.remove(normalizedArea)?.cancel();
    if (onLog == null) {
      _logByArea.remove(normalizedArea);
    } else {
      _logByArea[normalizedArea] = onLog;
      _logExpiryByArea[normalizedArea] = Timer(
        const Duration(seconds: 10),
        () {
          if ((_revisionByArea[normalizedArea] ?? 0) == nextRevision) {
            _logByArea.remove(normalizedArea);
          }
          _logExpiryByArea.remove(normalizedArea);
        },
      );
    }

    _emit(
      normalizedArea,
      '[OperationalSnapshotRevisionState] event=operational_snapshot_revision_emit area=$normalizedArea revision=$nextRevision consumers=sqlite_only transition=fade_translate firebaseAdditionalRead=0',
    );
    notifyListeners();
    return nextRevision;
  }

  void reportConsumerRefresh({
    required String area,
    required int revision,
    required String consumer,
    required String action,
  }) {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) return;
    if ((_revisionByArea[normalizedArea] ?? 0) != revision) return;

    _emit(
      normalizedArea,
      '[OperationalSnapshotRevisionState] event=consumer_refresh area=$normalizedArea revision=$revision consumer=$consumer action=$action transition=fade_translate firebaseAdditionalRead=0',
    );
  }

  void _emit(String area, String message) {
    final logger = _logByArea[area];
    if (logger == null) {
      debugPrint(message);
      return;
    }
    logger(message);
  }

  @override
  void dispose() {
    for (final timer in _logExpiryByArea.values) {
      timer.cancel();
    }
    _logExpiryByArea.clear();
    _logByArea.clear();
    super.dispose();
  }
}
