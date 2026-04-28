import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/init/db_connection_status_section.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/voice/application/voice_appbar_ui_state.dart';
import '../../../../features/voice/page/voice/widgets/voice_parking_completed_appbar_panel.dart';
import '../../real_time_table/view_doc_rows_firestore_sync.dart';

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
  final a1 = context.read<UserState>().currentArea.trim();
  final a2 = context.read<AreaState>().currentArea.trim();
  return a1.isNotEmpty ? a1 : a2;
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
    final bg = Theme.of(context).scaffoldBackgroundColor;

    final tint = resolveParkingCompletedLogoTint(
      background: bg,
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
    final cs = Theme.of(context).colorScheme;
    final tagPreferredTint = cs.onSurfaceVariant.withOpacity(0.80);
    final talkUiEnabled = context.watch<VoiceAppbarUiState>().enabled;

    return WillPopScope(
      onWillPop: onWillPop,
      child: Scaffold(
        backgroundColor: scaffoldBackgroundColor,
        appBar: AppBar(
          titleSpacing: talkUiEnabled ? 8 : NavigationToolbar.kMiddleSpacing,
          title: talkUiEnabled ? const SizedBox.shrink() : topNavigation,
          centerTitle: !talkUiEnabled,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: kToolbarHeight,
          shape: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withOpacity(0.85),
              width: 1,
            ),
          ),
          flexibleSpace: SafeArea(
            bottom: false,
            child: talkUiEnabled
                ? const VoiceParkingCompletedAppbarPanel()
                : Stack(
                    children: [
                      IgnorePointer(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12, top: 4),
                            child: Semantics(
                              label: semanticsLabel,
                              child: ExcludeSemantics(
                                child: ParkingCompletedBrandTintedLogo(
                                  assetPath: logoAssetPath,
                                  height: logoHeight,
                                  preferredColor: tagPreferredTint,
                                  fallbackColor: cs.onBackground,
                                  minContrast: logoMinContrast,
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
                                      alignment: Alignment.centerRight,
                                      child: DbConnectionStatusAppBarSection(
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
        body: Stack(
          children: [
            ViewDocRowsFirestoreSync(
              specs: syncSpecs,
              sourceTag: syncSourceTag,
            ),
            content,
          ],
        ),
      ),
    );
  }
}
