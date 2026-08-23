import 'dart:ui' show Rect;

import 'package:flutter/widgets.dart';

typedef TypePageQuickAction = Future<void> Function();
typedef TypePageEntryQuickAction = Future<void> Function(Rect sourceRect);

class TypePageQuickActionScope extends InheritedWidget {
  const TypePageQuickActionScope({
    super.key,
    required this.openEntry,
    required this.openSearch,
    required this.openDashboard,
    required super.child,
  });

  final TypePageEntryQuickAction openEntry;
  final TypePageQuickAction openSearch;
  final TypePageQuickAction openDashboard;

  static TypePageQuickActionScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TypePageQuickActionScope>();
  }

  @override
  bool updateShouldNotify(TypePageQuickActionScope oldWidget) {
    return openEntry != oldWidget.openEntry ||
        openSearch != oldWidget.openSearch ||
        openDashboard != oldWidget.openDashboard;
  }
}
