import 'package:flutter/material.dart';

import '../../../../../app/init/db_connection_status_section.dart';
import '../../../../../screens/minor_mode/type_package/common_widgets/dashboard_bottom_sheet/minor_hq_dash_board_page.dart';
import '../../../../../shared/page/widget/navigation/minor_top_navigation.dart';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final l1 = la >= lb ? la : lb;
  final l2 = la >= lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

Color _resolveLogoTint({
  required Color background,
  required Color preferred,
  required Color fallback,
  double minContrast = 3.0,
}) {
  if (_contrastRatio(preferred, background) >= minContrast) return preferred;
  return fallback;
}

class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
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
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;

    final tint = _resolveLogoTint(
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

class MinorDashBoard extends StatelessWidget {
  const MinorDashBoard({super.key});

  static const String screenTag = 'MinorHeadQuarter';
  static const String _kScreenTagAsset = 'assets/images/pelican_text.png';
  static const double _kScreenTagHeight = 54.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tagPreferredTint = cs.onSurfaceVariant.withOpacity(0.80);

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const MinorTopNavigation(),
          centerTitle: true,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withOpacity(0.85),
              width: 1,
            ),
          ),
          flexibleSpace: SafeArea(
            child: Stack(
              children: [
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12, top: 4),
                      child: Semantics(
                        label: 'screen_tag: MinorDashBoard C',
                        child: ExcludeSemantics(
                          child: _BrandTintedLogo(
                            assetPath: _kScreenTagAsset,
                            height: _kScreenTagHeight,
                            preferredColor: tagPreferredTint,
                            fallbackColor: cs.onBackground,
                            minContrast: 3.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding:
                      const EdgeInsets.only(right: 12, top: 8, bottom: 8),
                      child: SizedBox(
                        height: kToolbarHeight - 8,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 132),
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
              ],
            ),
          ),
        ),
        body: const MinorHqDashBoardPage(),
      ),
    );
  }
}