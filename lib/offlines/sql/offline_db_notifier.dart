import 'package:flutter/foundation.dart';

class OfflineDbNotifier {
  OfflineDbNotifier._();
  static final OfflineDbNotifier instance = OfflineDbNotifier._();

  /// DB 변경 알림용 tick. 값이 바뀌면 리스너들이 재빌드하도록 사용.
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// DB를 INSERT/UPDATE/DELETE 한 직후 호출
  void bump() {
    tick.value += 1;
    tick.value += 1;
  }
}
