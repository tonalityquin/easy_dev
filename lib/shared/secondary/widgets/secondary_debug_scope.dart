import 'package:flutter/widgets.dart';

class SecondaryDebugScope extends InheritedWidget {
  const SecondaryDebugScope({
    super.key,
    required this.onLog,
    required super.child,
  });

  final ValueChanged<String> onLog;

  static ValueChanged<String>? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<SecondaryDebugScope>()
        ?.onLog;
  }

  @override
  bool updateShouldNotify(SecondaryDebugScope oldWidget) {
    return onLog != oldWidget.onLog;
  }
}
