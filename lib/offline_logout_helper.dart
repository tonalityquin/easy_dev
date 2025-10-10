import 'package:flutter/material.dart';

import 'offlines/sql/offline_auth_service.dart';
import 'offlines/sql/offline_auth_db.dart';

class OfflineLogoutHelper {
  /// 세션을 지우고, 오프라인 번호판 데이터도 모두 삭제한 뒤
  /// 로그인 화면으로 이동(네비게이션 스택 제거)
  static Future<void> logoutAndGoToLogin(
      BuildContext context, {
        String? loginRoute,
        WidgetBuilder? loginBuilder,
      }) async {
    // 1) 번호판 데이터 완전 삭제 (오류가 나더라도 로그아웃/네비게이션은 계속 진행)
    try {
      await _wipeAllPlateData();
    } catch (_) {
      // 실패해도 흐름은 유지 (원하면 debugPrint로 로깅)
    }

    // 2) 오프라인 로그아웃(세션 정리)
    await OfflineAuthService.instance.signOutOffline();

    if (!context.mounted) return;

    // 3) 로그인 화면으로 이동 (스택 제거)
    if (loginRoute != null) {
      Navigator.pushNamedAndRemoveUntil(context, loginRoute, (route) => false);
    } else if (loginBuilder != null) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: loginBuilder),
            (route) => false,
      );
    } else {
      throw ArgumentError('loginRoute 또는 loginBuilder 중 하나는 필수입니다.');
    }
  }

  /// offline_plates 전체 삭제
  /// - 필요 시 WHERE 절을 추가해 특정 area/사용자 데이터만 삭제 가능
  static Future<void> _wipeAllPlateData() async {
    // DB가 닫혀 있으면 자동 재오픈
    await OfflineAuthDb.instance.reopenIfNeeded();
    final db = await OfflineAuthDb.instance.database;

    // 트랜잭션으로 안전하게 수행
    await db.transaction((txn) async {
      await txn.delete(OfflineAuthDb.tablePlates);
      // (선택) 자동증가 시퀀스도 초기화하려면 아래 주석 해제
      // await txn.rawDelete("DELETE FROM sqlite_sequence WHERE name = ?", [OfflineAuthDb.tablePlates]);
    });
  }
}
