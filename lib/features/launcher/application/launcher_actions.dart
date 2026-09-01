import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../app/di/routes.dart';
import '../../../app/init/app_exit_service.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../login/controllers/personal/personal_login_controller.dart';
import '../../login/pages/personal/personal_sign_up_dialog.dart';
import '../../selector/sheets/update_bottom_sheet.dart';
import 'launcher_diagnostics.dart';

class LauncherActions {
  const LauncherActions._();

  static const String supportUrl = 'https://forms.gle/hDTkX1p6U9jMMuySA';

  static Future<void> openAbout(BuildContext context) async {
    LauncherDiagnostics.record('open_about');
    await Navigator.of(context).pushNamed(AppRoutes.descriptionIntro);
  }

  static Future<void> openUpdate(BuildContext context) async {
    LauncherDiagnostics.record('open_update');
    final tokens = CommonUiTheme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: tokens.transparent,
      barrierColor: tokens.scrim,
      builder: (sheetContext) {
        return const CommonUiScope(
          child: FractionallySizedBox(
            heightFactor: 1,
            child: UpdateBottomSheet(),
          ),
        );
      },
    );
  }

  static Future<bool> openSupport() async {
    LauncherDiagnostics.record('open_support');
    try {
      final opened = await launchUrlString(
        supportUrl,
        mode: LaunchMode.externalApplication,
      );
      if (opened) return true;
    } catch (e) {
      LauncherDiagnostics.record(
        'open_support_external_failed',
        meta: <String, Object?>{'error': e},
      );
    }
    try {
      return await launchUrlString(
        supportUrl,
        mode: LaunchMode.platformDefault,
      );
    } catch (e) {
      LauncherDiagnostics.record(
        'open_support_default_failed',
        meta: <String, Object?>{'error': e},
      );
      return false;
    }
  }


  static Future<void> openPersonalSignup(BuildContext context) async {
    LauncherDiagnostics.record('open_personal_signup');
    final controller = PersonalLoginController(context);
    try {
      final developerMode = await controller.isDeveloperModeEnabled();
      if (!context.mounted) return;
      if (developerMode) {
        await showCommonDialog<bool>(
          context: context,
          barrierDismissible: !controller.isLoading,
          builder: (_) => PersonalSignUpDialog(controller: controller),
        );
        return;
      }
      await controller.openExternalSignUpForm();
    } finally {
      controller.dispose();
    }
  }

  static Future<void> openPractice(BuildContext context) async {
    LauncherDiagnostics.record('open_practice');
    await Navigator.of(context).pushNamed(AppRoutes.practiceSpaceLab);
  }

  static Future<void> openDev(BuildContext context) async {
    LauncherDiagnostics.record('open_dev');
    await Navigator.of(context).pushReplacementNamed(AppRoutes.devStub);
  }

  static Future<void> exitApp(BuildContext context) async {
    LauncherDiagnostics.record('exit_app');
    await AppExitService.exitApp(context, useCommonUi: true);
  }
}
