import 'dart:ui' show Rect;

import 'package:flutter/widgets.dart';

class RealTimeStatusActionScope extends InheritedWidget {
  const RealTimeStatusActionScope({
    super.key,
    required this.onOpenParentSelector,
    required super.child,
  });

  final Future<void> Function(Rect sourceRect, String currentParent)
      onOpenParentSelector;

  static RealTimeStatusActionScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RealTimeStatusActionScope>();
  }

  @override
  bool updateShouldNotify(covariant RealTimeStatusActionScope oldWidget) {
    return oldWidget.onOpenParentSelector != onOpenParentSelector;
  }
}
