import 'package:flutter/foundation.dart';

class OfflineDbNotifier {
  OfflineDbNotifier._();
  static final OfflineDbNotifier instance = OfflineDbNotifier._();

  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  void bump() {
    tick.value += 1;
    tick.value += 1;
  }
}
