import 'package:flutter/material.dart';
import '../../models/plate_model.dart';

/// 🔧 리팩터링 포인트:
/// - 이 State는 더 이상 Firestore 쓰기를 수행하지 않습니다.
/// - 서비스(ModifyPlateService)가 단일 update를 수행하므로 여기서는
///   UI 상태 업데이트/알림 용도로만 사용합니다.
class ModifyPlate with ChangeNotifier {
  ModifyPlate();

  /// 과거에는 이 메서드에서 addOrUpdatePlate / updatePlate를 호출했지만
  /// 이제는 서비스에서 통합 처리하므로 성공 신호만 반환하도록 축소.
  Future<bool> modifyPlateInfo({
    required BuildContext context,
    required PlateModel plate,
    required String newPlateNumber,
    required String location,
    required String collectionKey,
    String? billingType,
    List<String>? statusList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
    String? region,
    List<String>? imageUrls,
    bool? isLockedFee,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    int? regularAmount,
    int? regularDurationHours,
  }) async {
    // 로컬 상태 갱신 필요 시 여기서 처리(현재는 단순 성공 반환)
    notifyListeners();
    return true;
  }
}
