import 'package:flutter/material.dart';

class AreaChatAlertWatcher extends StatelessWidget {
  const AreaChatAlertWatcher({
    super.key,
    required this.areaNames,
    this.child,
    this.enabled = true,
    this.suppressedAreaNames = const <String>[],
  });

  final List<String> areaNames;
  final Widget? child;
  final bool enabled;
  final List<String> suppressedAreaNames;

  @override
  Widget build(BuildContext context) {
    return child ?? const SizedBox.shrink();
  }
}
