import 'package:provider/provider.dart';

import '../../../app/init/app_navigator.dart';
import '../../account/applications/user_state.dart';
import '../widgets/headquarter_quick_actions_side_dock.dart';
import 'headquarter_side_dock_launcher_controller.dart';

class HeadquarterSideDockCoordinator {
  HeadquarterSideDockCoordinator._();

  static bool _opening = false;

  static Future<void> open({
    String source = 'unknown',
  }) async {
    HeadquarterSideDockLauncherController.recordOpenRequested(source: source);

    if (!HeadquarterSideDockLauncherController.status.value.enabled) {
      HeadquarterSideDockLauncherController.recordOpenBlocked(
        source: source,
        reason: 'disabled',
      );
      return;
    }

    if (_opening) {
      HeadquarterSideDockLauncherController.recordOpenBlocked(
        source: source,
        reason: 'already_open',
      );
      return;
    }

    final context = AppNavigator.context;
    if (context == null || !context.mounted) {
      HeadquarterSideDockLauncherController.recordOpenBlocked(
        source: source,
        reason: 'context_unavailable',
      );
      return;
    }

    final userState = Provider.of<UserState>(context, listen: false);
    if (!userState.isLoggedIn) {
      HeadquarterSideDockLauncherController.recordOpenBlocked(
        source: source,
        reason: 'not_logged_in',
      );
      return;
    }

    _opening = true;
    var opened = false;

    try {
      HeadquarterSideDockLauncherController.recordOpened(source: source);
      opened = true;
      await showHeadquarterQuickActionsSideDock(
        context: context,
        source: source,
        useRootNavigator: true,
      );
    } catch (error, stackTrace) {
      HeadquarterSideDockLauncherController.recordOpenError(
        source: source,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _opening = false;
      if (opened) {
        HeadquarterSideDockLauncherController.recordClosed(source: source);
      }
    }
  }
}
