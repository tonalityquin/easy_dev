import 'package:flutter/widgets.dart';

typedef TypePageQuickAction = Future<void> Function();

class TypePageQuickActionScope extends InheritedWidget {
  const TypePageQuickActionScope({
    super.key,
    required this.openEntry,
    required this.openSearch,
    required this.openDashboard,
    required super.child,
  });

  final TypePageQuickAction openEntry;
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
