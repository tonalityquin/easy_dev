import 'package:flutter/material.dart';

import '../../../app/init/startup_tasks.dart';
import '../../../app/terminal/presentation/parkinworkin_terminal_screen.dart';

class ModeTerminalLauncherScreen extends StatelessWidget {
  const ModeTerminalLauncherScreen({
    super.key,
    this.startupReport,
  });

  final StartupReport? startupReport;

  @override
  Widget build(BuildContext context) {
    return ParkinWorkinTerminalScreen.launcher(
      startupReport: startupReport,
    );
  }
}
