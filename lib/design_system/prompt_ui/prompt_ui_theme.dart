import 'package:flutter/material.dart';

class PromptUiMotion {
  const PromptUiMotion._();

  static const Duration instant = Duration(milliseconds: 100);
  static const Duration press = Duration(milliseconds: 140);
  static const Duration selection = Duration(milliseconds: 190);
  static const Duration component = Duration(milliseconds: 230);
  static const Duration overlay = Duration(milliseconds: 280);
  static const Duration layout = Duration(milliseconds: 320);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve standard = Curves.easeInOutCubic;
}

class PromptUiShapes {
  const PromptUiShapes._();

  static const double control = 12;
  static const double button = 14;
  static const double card = 16;
  static const double dialog = 20;
  static const double sheet = 24;
  static const double pill = 999;
}

@immutable
class PromptUiTokens {
  const PromptUiTokens({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.surfaceSelected,
    required this.surfaceDisabled,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.iconDisabled,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentContainer,
    required this.onAccent,
    required this.onAccentContainer,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.focusRing,
    required this.scrim,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.statusParkingCompleted,
    required this.statusParkingCompletedContainer,
    required this.onStatusParkingCompletedContainer,
    required this.statusDepartureRequested,
    required this.statusDepartureRequestedContainer,
    required this.onStatusDepartureRequestedContainer,
    required this.statusSettlementPending,
    required this.statusSettlementPendingContainer,
    required this.onStatusSettlementPendingContainer,
    required this.statusMonthlyParking,
    required this.statusMonthlyParkingContainer,
    required this.onStatusMonthlyParkingContainer,
    required this.statusOffline,
    required this.statusOfflineContainer,
    required this.onStatusOfflineContainer,
    required this.statusSynchronized,
    required this.statusSynchronizedContainer,
    required this.onStatusSynchronizedContainer,
    required this.shadow,
    required this.handle,
    required this.transparent,
  });

  final Brightness brightness;
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceOverlay;
  final Color surfaceSelected;
  final Color surfaceDisabled;
  final Color borderSubtle;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconDisabled;
  final Color accent;
  final Color accentHover;
  final Color accentPressed;
  final Color accentContainer;
  final Color onAccent;
  final Color onAccentContainer;
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color focusRing;
  final Color scrim;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color statusParkingCompleted;
  final Color statusParkingCompletedContainer;
  final Color onStatusParkingCompletedContainer;
  final Color statusDepartureRequested;
  final Color statusDepartureRequestedContainer;
  final Color onStatusDepartureRequestedContainer;
  final Color statusSettlementPending;
  final Color statusSettlementPendingContainer;
  final Color onStatusSettlementPendingContainer;
  final Color statusMonthlyParking;
  final Color statusMonthlyParkingContainer;
  final Color onStatusMonthlyParkingContainer;
  final Color statusOffline;
  final Color statusOfflineContainer;
  final Color onStatusOfflineContainer;
  final Color statusSynchronized;
  final Color statusSynchronizedContainer;
  final Color onStatusSynchronizedContainer;
  final Color shadow;
  final Color handle;
  final Color transparent;

  bool get isDark => brightness == Brightness.dark;

  factory PromptUiTokens.fromTheme(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? const PromptUiTokens.dark()
        : const PromptUiTokens.light();
  }

  const PromptUiTokens.light()
      : brightness = Brightness.light,
        canvas = const Color(0xFFF2F6F5),
        surface = const Color(0xFFF8FBFA),
        surfaceRaised = const Color(0xFFFFFFFF),
        surfaceOverlay = const Color(0xFFE8F1EF),
        surfaceSelected = const Color(0xFFD7ECE8),
        surfaceDisabled = const Color(0xFFE4EBE9),
        borderSubtle = const Color(0xFFC8D7D3),
        borderStrong = const Color(0xFF8FA9A3),
        textPrimary = const Color(0xFF172421),
        textSecondary = const Color(0xFF4F625D),
        textDisabled = const Color(0xFF74827E),
        iconPrimary = const Color(0xFF172421),
        iconSecondary = const Color(0xFF4F625D),
        iconDisabled = const Color(0xFF7B8985),
        accent = const Color(0xFF1F7774),
        accentHover = const Color(0xFF196A67),
        accentPressed = const Color(0xFF145956),
        accentContainer = const Color(0xFFD4EAE7),
        onAccent = const Color(0xFFFFFFFF),
        onAccentContainer = const Color(0xFF124B48),
        success = const Color(0xFF0F7A46),
        onSuccess = const Color(0xFFFFFFFF),
        successContainer = const Color(0xFFDDF5E8),
        onSuccessContainer = const Color(0xFF0B4F31),
        warning = const Color(0xFF9B4F00),
        onWarning = const Color(0xFFFFFFFF),
        warningContainer = const Color(0xFFFFF0D7),
        onWarningContainer = const Color(0xFF613000),
        danger = const Color(0xFFB3261E),
        onDanger = const Color(0xFFFFFFFF),
        dangerContainer = const Color(0xFFFDE4E4),
        onDangerContainer = const Color(0xFF771A1A),
        info = const Color(0xFF1F6D99),
        onInfo = const Color(0xFFFFFFFF),
        infoContainer = const Color(0xFFDDF1FA),
        onInfoContainer = const Color(0xFF164B68),
        focusRing = const Color(0xFF2D8C88),
        scrim = const Color.fromRGBO(10, 20, 32, 0.42),
        shimmerBase = const Color(0xFFE1EAE8),
        shimmerHighlight = const Color(0xFFF7FAF9),
        statusParkingCompleted = const Color(0xFF0F7A46),
        statusParkingCompletedContainer = const Color(0xFFDDF5E8),
        onStatusParkingCompletedContainer = const Color(0xFF0B4F31),
        statusDepartureRequested = const Color(0xFFA64B00),
        statusDepartureRequestedContainer = const Color(0xFFFFE8CC),
        onStatusDepartureRequestedContainer = const Color(0xFF663000),
        statusSettlementPending = const Color(0xFF76519C),
        statusSettlementPendingContainer = const Color(0xFFF0E3FF),
        onStatusSettlementPendingContainer = const Color(0xFF49246A),
        statusMonthlyParking = const Color(0xFF1F6D99),
        statusMonthlyParkingContainer = const Color(0xFFDDF1FA),
        onStatusMonthlyParkingContainer = const Color(0xFF164B68),
        statusOffline = const Color(0xFF667085),
        statusOfflineContainer = const Color(0xFFEAECF0),
        onStatusOfflineContainer = const Color(0xFF344054),
        statusSynchronized = const Color(0xFF1F7774),
        statusSynchronizedContainer = const Color(0xFFD4EAE7),
        onStatusSynchronizedContainer = const Color(0xFF124B48),
        shadow = const Color.fromRGBO(12, 35, 31, 0.16),
        handle = const Color(0xFF879A95),
        transparent = Colors.transparent;

  const PromptUiTokens.dark()
      : brightness = Brightness.dark,
        canvas = const Color(0xFF0B1312),
        surface = const Color(0xFF111C1A),
        surfaceRaised = const Color(0xFF182522),
        surfaceOverlay = const Color(0xFF21312E),
        surfaceSelected = const Color(0xFF1B4540),
        surfaceDisabled = const Color(0xFF25312F),
        borderSubtle = const Color(0xFF304842),
        borderStrong = const Color(0xFF5A756E),
        textPrimary = const Color(0xFFF0F7F5),
        textSecondary = const Color(0xFFA9BBB6),
        textDisabled = const Color(0xFF71817D),
        iconPrimary = const Color(0xFFE5F0ED),
        iconSecondary = const Color(0xFFA9BBB6),
        iconDisabled = const Color(0xFF6F7E7A),
        accent = const Color(0xFF69C9C2),
        accentHover = const Color(0xFF82D7D0),
        accentPressed = const Color(0xFF48AAA4),
        accentContainer = const Color(0xFF18443F),
        onAccent = const Color(0xFF05211F),
        onAccentContainer = const Color(0xFFD2F4F0),
        success = const Color(0xFF54D18B),
        onSuccess = const Color(0xFF062818),
        successContainer = const Color(0xFF153D2A),
        onSuccessContainer = const Color(0xFFC7F5D9),
        warning = const Color(0xFFFFB85C),
        onWarning = const Color(0xFF2B1800),
        warningContainer = const Color(0xFF4B3215),
        onWarningContainer = const Color(0xFFFFE2B3),
        danger = const Color(0xFFFF7373),
        onDanger = const Color(0xFF2D0808),
        dangerContainer = const Color(0xFF4C2024),
        onDangerContainer = const Color(0xFFFFD1D1),
        info = const Color(0xFF69C5EF),
        onInfo = const Color(0xFF052433),
        infoContainer = const Color(0xFF163B4C),
        onInfoContainer = const Color(0xFFD4F2FF),
        focusRing = const Color(0xFF78DAD3),
        scrim = const Color.fromRGBO(0, 0, 0, 0.66),
        shimmerBase = const Color(0xFF1A2926),
        shimmerHighlight = const Color(0xFF2A3B37),
        statusParkingCompleted = const Color(0xFF54D18B),
        statusParkingCompletedContainer = const Color(0xFF153D2A),
        onStatusParkingCompletedContainer = const Color(0xFFC7F5D9),
        statusDepartureRequested = const Color(0xFFFFB45A),
        statusDepartureRequestedContainer = const Color(0xFF4A3013),
        onStatusDepartureRequestedContainer = const Color(0xFFFFE0AE),
        statusSettlementPending = const Color(0xFFD6A7FF),
        statusSettlementPendingContainer = const Color(0xFF3D2850),
        onStatusSettlementPendingContainer = const Color(0xFFF2DFFF),
        statusMonthlyParking = const Color(0xFF69C5EF),
        statusMonthlyParkingContainer = const Color(0xFF163B4C),
        onStatusMonthlyParkingContainer = const Color(0xFFD4F2FF),
        statusOffline = const Color(0xFF98A2B3),
        statusOfflineContainer = const Color(0xFF2B313A),
        onStatusOfflineContainer = const Color(0xFFE4E7EC),
        statusSynchronized = const Color(0xFF69C9C2),
        statusSynchronizedContainer = const Color(0xFF18443F),
        onStatusSynchronizedContainer = const Color(0xFFD2F4F0),
        shadow = const Color.fromRGBO(0, 0, 0, 0.46),
        handle = const Color(0xFF718A84),
        transparent = Colors.transparent;
}

class PromptUiTheme {
  const PromptUiTheme._();

  static const String fontFamily = 'NotoSansKR';

  static PromptUiTokens of(BuildContext context) {
    return PromptUiTokens.fromTheme(Theme.of(context));
  }

  static ThemeData scoped(ThemeData base) {
    final tokens = PromptUiTokens.fromTheme(base);
    final textTheme = _withFont(base.textTheme).apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
    );
    final primaryTextTheme = _withFont(base.primaryTextTheme).apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
    );
    final colorScheme = _colorScheme(base.colorScheme, tokens);

    return base.copyWith(
      colorScheme: colorScheme,
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      cardColor: tokens.surfaceRaised,
      disabledColor: tokens.textDisabled,
      dividerColor: tokens.borderSubtle,
      shadowColor: tokens.shadow,
      splashColor: tokens.accent.withOpacity(tokens.isDark ? 0.18 : 0.12),
      highlightColor: tokens.accent.withOpacity(tokens.isDark ? 0.12 : 0.08),
      hoverColor: tokens.accent.withOpacity(tokens.isDark ? 0.12 : 0.07),
      focusColor: tokens.focusRing.withOpacity(tokens.isDark ? 0.22 : 0.14),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: tokens.transparent,
        shadowColor: tokens.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: tokens.iconPrimary),
        actionsIconTheme: IconThemeData(color: tokens.iconPrimary),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      iconTheme: IconThemeData(color: tokens.iconPrimary),
      primaryIconTheme: IconThemeData(color: tokens.iconPrimary),
      dividerTheme: base.dividerTheme.copyWith(
        color: tokens.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: tokens.surfaceRaised,
        surfaceTintColor: tokens.transparent,
        shadowColor: tokens.shadow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          side: BorderSide(color: tokens.borderSubtle),
        ),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: tokens.transparent,
        surfaceTintColor: tokens.transparent,
        modalBackgroundColor: tokens.transparent,
        modalBarrierColor: tokens.scrim,
        shadowColor: tokens.shadow,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: tokens.surfaceRaised,
        surfaceTintColor: tokens.transparent,
        shadowColor: tokens.shadow,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: tokens.textSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.dialog),
          side: BorderSide(color: tokens.borderSubtle),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tokens.surface,
        selectedColor: tokens.accentContainer,
        disabledColor: tokens.surfaceDisabled,
        surfaceTintColor: tokens.transparent,
        shadowColor: tokens.shadow,
        selectedShadowColor: tokens.shadow,
        side: BorderSide(color: tokens.borderSubtle),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        ),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: tokens.onAccentContainer,
          fontWeight: FontWeight.w700,
        ),
        checkmarkColor: tokens.accentPressed,
        iconTheme: IconThemeData(color: tokens.iconSecondary),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: tokens.surface,
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: tokens.accentPressed,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: tokens.iconSecondary,
        suffixIconColor: tokens.iconSecondary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          borderSide: BorderSide(color: tokens.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          borderSide: BorderSide(color: tokens.focusRing, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          borderSide: BorderSide(color: tokens.borderSubtle),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          borderSide: BorderSide(color: tokens.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          borderSide: BorderSide(color: tokens.danger, width: 2),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tokens.accent,
        selectionColor: tokens.accent.withOpacity(tokens.isDark ? 0.34 : 0.24),
        selectionHandleColor: tokens.accent,
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        color: tokens.accent,
        linearTrackColor: tokens.surfaceDisabled,
        circularTrackColor: tokens.surfaceDisabled,
      ),
      tooltipTheme: base.tooltipTheme.copyWith(
        textStyle: textTheme.bodySmall?.copyWith(
          color: tokens.surfaceRaised,
          fontWeight: FontWeight.w500,
        ),
        decoration: BoxDecoration(
          color: tokens.textPrimary,
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          border: Border.all(color: tokens.borderStrong),
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: tokens.surfaceRaised,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: tokens.accent,
        disabledActionTextColor: tokens.textDisabled,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          side: BorderSide(color: tokens.borderSubtle),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.iconDisabled;
          }
          if (states.contains(WidgetState.selected)) {
            return tokens.onAccent;
          }
          return tokens.iconSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.surfaceDisabled;
          }
          if (states.contains(WidgetState.selected)) {
            return tokens.accent;
          }
          return tokens.surfaceOverlay;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.accentPressed;
          }
          return tokens.borderStrong;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.surfaceDisabled;
          }
          if (states.contains(WidgetState.selected)) {
            return tokens.accent;
          }
          return tokens.surface;
        }),
        checkColor: WidgetStatePropertyAll(tokens.onAccent),
        side: BorderSide(color: tokens.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.iconDisabled;
          }
          if (states.contains(WidgetState.selected)) {
            return tokens.accent;
          }
          return tokens.iconSecondary;
        }),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: tokens.accent,
        inactiveTrackColor: tokens.surfaceDisabled,
        thumbColor: tokens.accent,
        overlayColor: tokens.accent.withOpacity(tokens.isDark ? 0.22 : 0.14),
        valueIndicatorColor: tokens.textPrimary,
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: tokens.surfaceRaised,
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        iconColor: tokens.iconSecondary,
        textColor: tokens.textPrimary,
        selectedColor: tokens.accentPressed,
        selectedTileColor: tokens.surfaceSelected,
        tileColor: tokens.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.surfaceDisabled;
            }
            if (states.contains(WidgetState.pressed)) {
              return tokens.accentPressed;
            }
            if (states.contains(WidgetState.hovered)) {
              return tokens.accentHover;
            }
            return tokens.accent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.textDisabled;
            }
            return tokens.onAccent;
          }),
          overlayColor: WidgetStatePropertyAll(
            tokens.onAccent.withOpacity(tokens.isDark ? 0.12 : 0.08),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PromptUiShapes.button),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.surfaceDisabled;
            }
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered)) {
              return tokens.surfaceSelected;
            }
            return tokens.accentContainer;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.textDisabled;
            }
            return tokens.onAccentContainer;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: tokens.borderSubtle);
            }
            return BorderSide(color: tokens.accent);
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PromptUiShapes.button),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.textDisabled;
            }
            if (states.contains(WidgetState.pressed)) {
              return tokens.accentPressed;
            }
            return tokens.accent;
          }),
          overlayColor: WidgetStatePropertyAll(
            tokens.accent.withOpacity(tokens.isDark ? 0.14 : 0.08),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  static ColorScheme _colorScheme(
    ColorScheme base,
    PromptUiTokens tokens,
  ) {
    return base.copyWith(
      primary: tokens.accent,
      onPrimary: tokens.onAccent,
      primaryContainer: tokens.accentContainer,
      onPrimaryContainer: tokens.onAccentContainer,
      secondary: tokens.accent,
      onSecondary: tokens.onAccent,
      secondaryContainer: tokens.accentContainer,
      onSecondaryContainer: tokens.onAccentContainer,
      tertiary: tokens.info,
      onTertiary: tokens.onInfo,
      tertiaryContainer: tokens.infoContainer,
      onTertiaryContainer: tokens.onInfoContainer,
      error: tokens.danger,
      onError: tokens.onDanger,
      errorContainer: tokens.dangerContainer,
      onErrorContainer: tokens.onDangerContainer,
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
      surfaceDim: tokens.canvas,
      surfaceBright: tokens.surfaceRaised,
      surfaceContainerLowest: tokens.canvas,
      surfaceContainerLow: tokens.surface,
      surfaceContainer: tokens.surfaceOverlay,
      surfaceContainerHigh: tokens.surfaceSelected,
      surfaceContainerHighest: tokens.surfaceDisabled,
      onSurfaceVariant: tokens.textSecondary,
      outline: tokens.borderStrong,
      outlineVariant: tokens.borderSubtle,
      shadow: tokens.shadow,
      scrim: tokens.scrim,
      inverseSurface:
          tokens.isDark ? const Color(0xFFE4EFEC) : const Color(0xFF22302D),
      onInverseSurface:
          tokens.isDark ? const Color(0xFF172421) : const Color(0xFFF0F7F5),
      inversePrimary:
          tokens.isDark ? const Color(0xFF1F7774) : const Color(0xFF8FE0DA),
      surfaceTint: tokens.transparent,
    );
  }

  static TextTheme _withFont(TextTheme source) {
    return source.apply(fontFamily: fontFamily).copyWith(
          displayLarge: source.displayLarge?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ),
          displayMedium: source.displayMedium?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ),
          headlineLarge: source.headlineLarge?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: source.headlineMedium?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: source.titleLarge?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: source.titleMedium?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: source.titleSmall?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: source.bodyLarge?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w400,
            height: 1.42,
          ),
          bodyMedium: source.bodyMedium?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w400,
            height: 1.42,
          ),
          bodySmall: source.bodySmall?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w400,
            height: 1.38,
          ),
          labelLarge: source.labelLarge?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: source.labelMedium?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: source.labelSmall?.copyWith(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w500,
          ),
        );
  }
}

class PromptUiScope extends StatelessWidget {
  const PromptUiScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedTheme(
      data: PromptUiTheme.scoped(Theme.of(context)),
      duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
      curve: PromptUiMotion.standard,
      child: child,
    );
  }
}
