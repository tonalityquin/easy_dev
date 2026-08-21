import 'dart:async';

import 'package:flutter/foundation.dart';

class RealTimeParentFocusRequest {
  const RealTimeParentFocusRequest({
    required this.serial,
    required this.parent,
  });

  final int serial;
  final String parent;
}

class RealTimeTabController {
  RealTimeTabController({this.debugLabel = ''});

  final String debugLabel;
  Future<void> Function()? _refreshUser;
  Object? _bindingOwner;
  Completer<void>? _boundCompleter;
  final List<String> _debugLines = <String>[];
  ValueChanged<RealTimeParentFocusRequest>? _parentFocusUser;
  Object? _parentFocusOwner;
  RealTimeParentFocusRequest? _pendingParentFocus;
  int _parentFocusSerial = 0;
  String _activeParent = '';

  bool get isBound => _refreshUser != null && _bindingOwner != null;

  List<String> debugLinesSnapshot() => List<String>.unmodifiable(_debugLines);

  String get activeParent => _activeParent;

  void bindParentFocus(
    Object owner,
    ValueChanged<RealTimeParentFocusRequest> onParentFocus,
  ) {
    final previousOwner = _parentFocusOwner;
    _parentFocusOwner = owner;
    _parentFocusUser = onParentFocus;
    _debugLog(
      'parent_focus_bind',
      <String, Object?>{
        'owner': _ownerLabel(owner),
        'previousOwner': previousOwner == null ? null : _ownerLabel(previousOwner),
        'pending': _pendingParentFocus?.parent,
      },
    );
    final pending = _pendingParentFocus;
    if (pending == null) return;
    _pendingParentFocus = null;
    scheduleMicrotask(() {
      if (!identical(_parentFocusOwner, owner)) {
        _pendingParentFocus = pending;
        return;
      }
      _debugLog(
        'parent_focus_pending_dispatched',
        <String, Object?>{
          'serial': pending.serial,
          'parent': pending.parent,
          'owner': _ownerLabel(owner),
        },
      );
      onParentFocus(pending);
    });
  }

  void unbindParentFocus(Object owner) {
    if (!identical(_parentFocusOwner, owner)) return;
    _debugLog(
      'parent_focus_unbind',
      <String, Object?>{'owner': _ownerLabel(owner)},
    );
    _parentFocusOwner = null;
    _parentFocusUser = null;
  }

  RealTimeParentFocusRequest requestParentFocus(
    String parent, {
    bool deferUntilNextBind = false,
  }) {
    final normalized = parent.trim();
    final request = RealTimeParentFocusRequest(
      serial: ++_parentFocusSerial,
      parent: normalized,
    );
    final handler = _parentFocusUser;
    final owner = _parentFocusOwner;
    if (deferUntilNextBind || handler == null || owner == null) {
      _pendingParentFocus = request;
      _debugLog(
        'parent_focus_queued',
        <String, Object?>{
          'serial': request.serial,
          'parent': request.parent,
          'deferUntilNextBind': deferUntilNextBind,
        },
      );
      return request;
    }
    _debugLog(
      'parent_focus_dispatched',
      <String, Object?>{
        'serial': request.serial,
        'parent': request.parent,
        'owner': _ownerLabel(owner),
      },
    );
    handler(request);
    return request;
  }

  void reportActiveParent(String parent) {
    final normalized = parent.trim();
    if (_activeParent == normalized) return;
    _activeParent = normalized;
    _debugLog(
      'active_parent_reported',
      <String, Object?>{'parent': normalized},
    );
  }

  void bind(Object owner, Future<void> Function() refreshUser) {
    final previousOwner = _bindingOwner;
    _bindingOwner = owner;
    _refreshUser = refreshUser;
    _debugLog(
      'bind',
      <String, Object?>{
        'owner': _ownerLabel(owner),
        'previousOwner': previousOwner == null ? null : _ownerLabel(previousOwner),
      },
    );
    final c = _boundCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _boundCompleter = null;
  }

  void unbind(Object owner) {
    if (!identical(_bindingOwner, owner)) {
      _debugLog(
        'unbind_ignored',
        <String, Object?>{
          'requestOwner': _ownerLabel(owner),
          'activeOwner': _bindingOwner == null ? null : _ownerLabel(_bindingOwner!),
        },
      );
      return;
    }
    _debugLog(
      'unbind',
      <String, Object?>{'owner': _ownerLabel(owner)},
    );
    _bindingOwner = null;
    _refreshUser = null;
  }

  void forceUnbind({String reason = 'force'}) {
    final previousOwner = _bindingOwner;
    _bindingOwner = null;
    _refreshUser = null;
    _parentFocusOwner = null;
    _parentFocusUser = null;
    _debugLog(
      'force_unbind',
      <String, Object?>{
        'reason': reason,
        'previousOwner': previousOwner == null ? null : _ownerLabel(previousOwner),
      },
    );
  }

  Future<void> waitUntilBound() {
    if (isBound) return Future.value();
    _boundCompleter ??= Completer<void>();
    return _boundCompleter!.future;
  }

  Future<void> refreshUser() async {
    final f = _refreshUser;
    final owner = _bindingOwner;
    if (f == null || owner == null) {
      _debugLog('refresh_skipped_unbound');
      return;
    }
    _debugLog(
      'refresh_dispatched',
      <String, Object?>{'owner': _ownerLabel(owner)},
    );
    await f();
  }

  String _ownerLabel(Object owner) =>
      '${owner.runtimeType}@${identityHashCode(owner).toRadixString(16)}';

  void _debugLog(
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    final buffer = StringBuffer()
      ..write('[RealTimeTabController] ')
      ..write(DateTime.now().toIso8601String())
      ..write(' event=')
      ..write(event);
    if (debugLabel.trim().isNotEmpty) {
      buffer
        ..write(' tab=')
        ..write(debugLabel.trim());
    }
    for (final entry in details.entries) {
      if (entry.value == null) continue;
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    final line = buffer.toString();
    _debugLines.add(line);
    if (_debugLines.length > 120) {
      _debugLines.removeRange(0, _debugLines.length - 120);
    }
    debugPrint(line);
  }
}
