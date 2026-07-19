import 'package:flutter/material.dart';

import '../../design_system/prompt_ui/prompt_ui_theme.dart';

class PhotoTransferButtonStyles {
  const PhotoTransferButtonStyles._();

  static ButtonStyle primary(
    BuildContext context, {
    double minHeight = 55,
  }) {
    final tokens = PromptUiTheme.of(context);
    return ElevatedButton.styleFrom(
      backgroundColor: tokens.accent,
      foregroundColor: tokens.onAccent,
      disabledBackgroundColor: tokens.surfaceDisabled,
      disabledForegroundColor: tokens.textDisabled,
      minimumSize: Size(0, minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      side: BorderSide(color: tokens.accentPressed.withOpacity(0.55)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.button),
      ),
      elevation: 0,
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.pressed)
            ? tokens.onAccent.withOpacity(0.10)
            : null,
      ),
    );
  }

  static ButtonStyle outlined(
    BuildContext context, {
    double minHeight = 55,
  }) {
    final tokens = PromptUiTheme.of(context);
    return OutlinedButton.styleFrom(
      foregroundColor: tokens.onAccentContainer,
      backgroundColor: tokens.accentContainer,
      disabledForegroundColor: tokens.textDisabled,
      disabledBackgroundColor: tokens.surfaceDisabled,
      side: BorderSide(color: tokens.accent.withOpacity(0.46)),
      minimumSize: Size(0, minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.button),
      ),
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.pressed)
            ? tokens.accent.withOpacity(0.12)
            : null,
      ),
    );
  }

  static ButtonStyle smallPrimary(BuildContext context) =>
      primary(context, minHeight: 44);

  static ButtonStyle smallOutlined(BuildContext context) =>
      outlined(context, minHeight: 44);
}
