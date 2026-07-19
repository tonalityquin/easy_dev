import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../../app/init/db_connection_status_section.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../../features/account/applications/user_state.dart';
import '../../../../../features/dev/application/area_state.dart';
import '../../../../../features/voice/application/voice_appbar_ui_state.dart';
import '../../../../../features/voice/presentation/appbar/voice_parking_completed_appbar_panel.dart';
import '../../../../real_time_table/view_doc_rows_firestore_sync.dart';

double parkingCompletedContrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final l1 = la >= lb ? la : lb;
  final l2 = la >= lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

Color resolveParkingCompletedLogoTint({
  required Color background,
  required Color preferred,
  required Color fallback,
  double minContrast = 3.0,
}) {
  if (parkingCompletedContrastRatio(preferred, background) >= minContrast) {
    return preferred;
  }
  return fallback;
}

String resolveParkingCompletedArea(BuildContext context) {
  final userArea = context.read<UserState>().currentArea.trim();
  final selectedArea = context.read<AreaState>().currentArea.trim();
  return userArea.isNotEmpty ? userArea : selectedArea;
}

class ParkingCompletedBrandTintedLogo extends StatelessWidget {
  const ParkingCompletedBrandTintedLogo({
    super.key,
    required this.assetPath,
    required this.height,
    required this.preferredColor,
    required this.fallbackColor,
    this.minContrast = 3.0,
  });

  final String assetPath;
  final double height;
  final Color preferredColor;
  final Color fallbackColor;
  final double minContrast;

  @override
  Widget build(BuildContext context) {
    final background = PromptUiTheme.of(context).surface;
    final tint = resolveParkingCompletedLogoTint(
      background: background,
      preferred: preferredColor,
      fallback: fallbackColor,
      minContrast: minContrast,
    );

    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
    );
  }
}

class ParkingCompletedPageShell extends StatelessWidget {
  const ParkingCompletedPageShell({
    super.key,
    required this.topNavigation,
    required this.semanticsLabel,
    required this.syncSourceTag,
    required this.syncSpecs,
    required this.content,
    required this.onWillPop,
    this.scaffoldBackgroundColor,
    this.logoAssetPath = 'assets/images/pelican_text.png',
    this.logoHeight = 54.0,
    this.logoMinContrast = 3.0,
    this.showDbStatusOnAppBar = true,
  });

  final Widget topNavigation;
  final String semanticsLabel;
  final String syncSourceTag;
  final List<ViewDocSyncSpec> syncSpecs;
  final Widget content;
  final Future<bool> Function() onWillPop;
  final Color? scaffoldBackgroundColor;
  final String logoAssetPath;
  final double logoHeight;
  final double logoMinContrast;
  final bool showDbStatusOnAppBar;

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(
        builder: (context) {
          final tokens = PromptUiTheme.of(context);
          final reduceMotion =
              MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          final talkUiEnabled = context.watch<VoiceAppbarUiState>().enabled;
          final isDark = tokens.brightness == Brightness.dark;
          final preferredTint = tokens.accent;

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: tokens.surface,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              statusBarBrightness:
                  isDark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: tokens.surface,
              systemNavigationBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
            ),
            child: WillPopScope(
              onWillPop: onWillPop,
              child: Scaffold(
                backgroundColor: scaffoldBackgroundColor ?? tokens.canvas,
                appBar: AppBar(
                  titleSpacing:
                      talkUiEnabled ? 8 : NavigationToolbar.kMiddleSpacing,
                  title: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : PromptUiMotion.component,
                    switchInCurve: PromptUiMotion.enter,
                    switchOutCurve: PromptUiMotion.exit,
                    child: talkUiEnabled
                        ? const SizedBox.shrink(
                            key: ValueKey<String>('talk-title'),
                          )
                        : KeyedSubtree(
                            key: const ValueKey<String>('navigation-title'),
                            child: topNavigation,
                          ),
                  ),
                  centerTitle: !talkUiEnabled,
                  backgroundColor: tokens.surface,
                  foregroundColor: tokens.textPrimary,
                  elevation: 0,
                  surfaceTintColor: tokens.transparent,
                  shadowColor: tokens.transparent,
                  toolbarHeight: kToolbarHeight,
                  shape: Border(
                    bottom: BorderSide(color: tokens.borderSubtle),
                  ),
                  flexibleSpace: SafeArea(
                    bottom: false,
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : PromptUiMotion.component,
                      switchInCurve: PromptUiMotion.enter,
                      switchOutCurve: PromptUiMotion.exit,
                      transitionBuilder: (child, animation) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: PromptUiMotion.enter,
                          reverseCurve: PromptUiMotion.exit,
                        );
                        return FadeTransition(opacity: curved, child: child);
                      },
                      child: talkUiEnabled
                          ? const VoiceParkingCompletedAppbarPanel(
                              key: ValueKey<String>('talk-panel'),
                            )
                          : Stack(
                              key: const ValueKey<String>('standard-panel'),
                              children: [
                                IgnorePointer(
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 12,
                                        top: 4,
                                      ),
                                      child: Semantics(
                                        label: semanticsLabel,
                                        child: ExcludeSemantics(
                                          child: PromptAnimatedReveal(
                                            offset: const Offset(-0.035, 0),
                                            child:
                                                ParkingCompletedBrandTintedLogo(
                                              assetPath: logoAssetPath,
                                              height: logoHeight,
                                              preferredColor: preferredTint,
                                              fallbackColor: tokens.textPrimary,
                                              minContrast: logoMinContrast,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (showDbStatusOnAppBar)
                                  IgnorePointer(
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 12,
                                          top: 4,
                                          bottom: 4,
                                        ),
                                        child: SizedBox(
                                          height: kToolbarHeight - 8,
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 132,
                                                maxHeight: kToolbarHeight - 8,
                                              ),
                                              child: const FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment:
                                                    Alignment.centerRight,
                                                child:
                                                    DbConnectionStatusAppBarSection(
                                                  liveLabel: 'live DB',
                                                  storageLabel: '스토리지 DB',
                                                  spacing: 4,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ),
                body: Stack(
                  children: [
                    ViewDocRowsFirestoreSync(
                      specs: syncSpecs,
                      sourceTag: syncSourceTag,
                    ),
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : PromptUiMotion.component,
                      switchInCurve: PromptUiMotion.enter,
                      switchOutCurve: PromptUiMotion.exit,
                      child: KeyedSubtree(
                        key: ValueKey<String>(syncSourceTag),
                        child: content,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
