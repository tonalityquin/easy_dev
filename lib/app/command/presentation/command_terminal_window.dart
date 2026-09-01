import 'package:flutter/material.dart';

import '../../terminal/presentation/parkinworkin_terminal_navigator.dart';

Future<void> showCommandTerminal(
  BuildContext context, {
  String source = 'command_launcher',
}) {
  return showParkinWorkinTerminal(
    context,
    source: source,
  );
}
