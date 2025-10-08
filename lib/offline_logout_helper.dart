import 'package:flutter/material.dart';
import 'offlines/sql/offline_auth_service.dart';

class OfflineLogoutHelper {
  /// 세션을 지우고 로그인 화면으로 이동(스택 제거)
  static Future<void> logoutAndGoToLogin(
      BuildContext context, {
        String? loginRoute,
        WidgetBuilder? loginBuilder,
      }) async {
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
}
