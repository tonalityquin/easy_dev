import 'package:flutter/material.dart';

import '../sql/offline_auth_service.dart';
import '../sql/offline_auth_db.dart';

class OfflineLogoutHelper {
  static Future<void> logoutAndGoToLogin(
      BuildContext context, {
        String? loginRoute,
        WidgetBuilder? loginBuilder,
      }) async {
    try {
      await _wipeAllPlateData();
    } catch (_) {
    }

    await OfflineAuthService.instance.signOutOffline();

    if (!context.mounted) return;

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

  static Future<void> _wipeAllPlateData() async {
    await OfflineAuthDb.instance.reopenIfNeeded();
    final db = await OfflineAuthDb.instance.database;

    await db.transaction((txn) async {
      await txn.delete(OfflineAuthDb.tablePlates);
    });
  }
}
