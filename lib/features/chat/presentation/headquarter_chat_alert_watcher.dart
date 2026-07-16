import 'package:flutter/material.dart';

class HeadquarterChatAlertWatcher extends StatelessWidget {
  const HeadquarterChatAlertWatcher({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
