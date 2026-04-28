import 'dart:async';

class RealTimeTabController {
  Future<void> Function()? _refreshUser;
  Completer<void>? _boundCompleter;

  bool get isBound => _refreshUser != null;

  void bind(Future<void> Function() refreshUser) {
    _refreshUser = refreshUser;
    final c = _boundCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _boundCompleter = null;
  }

  void unbind() {
    _refreshUser = null;
  }

  Future<void> waitUntilBound() {
    if (isBound) return Future.value();
    _boundCompleter ??= Completer<void>();
    return _boundCompleter!.future;
  }

  Future<void> refreshUser() async {
    final f = _refreshUser;
    if (f == null) return;
    await f();
  }
}
