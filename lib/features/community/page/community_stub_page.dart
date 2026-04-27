import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/di/routes.dart';
import '../application/discord/discord_config.dart';
import 'sheets/discord/discord_bottom_sheet.dart';
import 'sheets/game/game_arcade_bottom_sheet.dart';

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
  const _BrandTintedLogo({required this.height});

  static const String _assetPath = 'assets/images/ParkinWorkin_text.png';
  static const double _minContrast = 3.0;

  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = _resolveLogoTint(
      background: cs.background,
      preferred: cs.primary,
      fallback: cs.onBackground,
      minContrast: _minContrast,
    );

    return Image.asset(
      _assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

@immutable
class _CommunityTokens {
  const _CommunityTokens({
    required this.pageBackground,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.divider,
    required this.cardSurface,
    required this.cardBorder,
    required this.title,
    required this.subtitle,
  });

  final Color pageBackground;
  final Color appBarBackground;
  final Color appBarForeground;
  final Color divider;
  final Color cardSurface;
  final Color cardBorder;
  final Color title;
  final Color subtitle;

  factory _CommunityTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _CommunityTokens(
      pageBackground: cs.background,
      appBarBackground: cs.background,
      appBarForeground: cs.onSurface,
      divider: cs.outlineVariant,
      cardSurface: cs.surface,
      cardBorder: cs.outlineVariant.withOpacity(0.85),
      title: cs.onSurface,
      subtitle: cs.onSurfaceVariant,
    );
  }
}

class CommunityStubPage extends StatelessWidget {
  const CommunityStubPage({super.key});

  static const String _termsOfServiceUrl =
      'https://sites.google.com/view/parkinworkin3/%ED%99%88';
  static const String _privacyPolicyUrl =
      'https://sites.google.com/view/parkinworkin4/%ED%99%88';

  Future<bool?> _openWalkieTutorial(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DiscordBottomSheet(rootContext: context),
    );
  }

  Future<bool> _tryOpenExternalUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> _openExternalPage(String url) async {
    await _tryOpenExternalUrl(url);
  }

  Future<void> _openTermsOfService() async {
    await _openExternalPage(_termsOfServiceUrl);
  }

  Future<void> _openPrivacyPolicy() async {
    await _openExternalPage(_privacyPolicyUrl);
  }

  Future<void> _openWalkieFlow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(discordWalkieTutorialDoneKey) ?? false;
    final inviteUrl = prefs.getString(discordWalkieInviteUrlKey) ?? '';

    if (done && isDiscordInviteUrl(inviteUrl)) {
      final ok = await _tryOpenExternalUrl(inviteUrl);
      if (ok) return;
    }

    if (!context.mounted) return;

    final completed = await _openWalkieTutorial(context);
    if (completed != true) return;

    final prefs2 = await SharedPreferences.getInstance();
    final inviteUrl2 = prefs2.getString(discordWalkieInviteUrlKey) ?? '';
    if (isDiscordInviteUrl(inviteUrl2)) {
      await _tryOpenExternalUrl(inviteUrl2);
    }
  }

  Future<void> _openArcadeSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GameArcadeBottomSheet(rootContext: context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _CommunityTokens.of(context);
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final media = MediaQuery.of(context);
    final isShort = media.size.height < 640;
    final keyboardOpen = media.viewInsets.bottom > 0;
    final footerHeight = (isShort || keyboardOpen) ? 72.0 : 120.0;

    return Scaffold(
      backgroundColor: tokens.pageBackground,
      appBar: AppBar(
        backgroundColor: tokens.appBarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: true,
        leading: const BackButton(),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        title: Text(
          '커뮤니티 허브',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: tokens.appBarForeground,
          ),
        ),
        iconTheme: IconThemeData(color: tokens.appBarForeground),
        actionsIconTheme: IconThemeData(color: tokens.appBarForeground),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: tokens.divider),
        ),
      ),
      body: SafeArea(
        child: Container(
          color: tokens.pageBackground,
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeaderBanner(),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = width >= 1100
                        ? 4
                        : width >= 800
                            ? 3
                            : 2;

                    const spacing = 12.0;
                    final textScale =
                        MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);
                    final tileWidth = (width - spacing * (crossAxisCount - 1)) /
                        crossAxisCount;
                    const baseTileHeight = 150.0;
                    final tileHeight = baseTileHeight * textScale;
                    final childAspectRatio = tileWidth / tileHeight;

                    final cards = <Widget>[
                      _ActionCard(
                        icon: Icons.record_voice_over_rounded,
                        title: '무전기',
                        subtitle: '근무지 음성 채널',
                        accent: cs.primary,
                        onAccent: cs.onPrimary,
                        onTap: () => Navigator.of(context)
                            .pushNamed(AppRoutes.communityWorkintalkin),
                      ),
                      _ActionCard(
                        icon: Icons.mic_rounded,
                        title: '사내 업무 커뮤니티',
                        subtitle: 'Discord',
                        accent: cs.secondary,
                        onAccent: cs.onSecondary,
                        onTap: () => _openWalkieFlow(context),
                        onLongPress: () => _openWalkieTutorial(context),
                      ),
                      _ActionCard(
                        icon: Icons.videogame_asset_rounded,
                        title: '아케이드',
                        subtitle: 'Arcade',
                        accent: cs.secondary,
                        onAccent: cs.onSecondary,
                        onTap: () => _openArcadeSheet(context),
                      ),
                      _ActionCard(
                        icon: Icons.description_rounded,
                        title: '이용약관',
                        subtitle: '서비스 이용 안내',
                        accent: cs.tertiary,
                        onAccent: cs.onTertiary,
                        onTap: _openTermsOfService,
                      ),
                      _ActionCard(
                        icon: Icons.privacy_tip_rounded,
                        title: '개인정보보호처리방침',
                        subtitle: '개인정보 처리 안내',
                        accent: cs.primaryContainer,
                        onAccent: cs.onPrimaryContainer,
                        onTap: _openPrivacyPolicy,
                      ),
                    ];

                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemCount: cards.length,
                      itemBuilder: (context, i) => cards[i],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AnimatedOpacity(
        opacity: keyboardOpen ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 160),
        child: SafeArea(
          top: false,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.pageBackground,
              border: Border(top: BorderSide(color: tokens.divider, width: 1)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: null,
                child: SizedBox(
                  height: footerHeight,
                  child: Center(
                    child: _BrandTintedLogo(height: footerHeight),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final base = cs.secondary;
    final container = cs.secondaryContainer;
    final onContainer = cs.onSecondaryContainer;
    final border = cs.outlineVariant.withOpacity(0.85);
    final bg0 = Color.alphaBlend(container.withOpacity(0.92), cs.background);
    final bg1 = Color.alphaBlend(base.withOpacity(0.10), cs.background);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg0, bg1],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: base.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: base.withOpacity(0.22)),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.groups_rounded, color: base),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '커뮤니티 허브 입니다.',
              style: text.bodyMedium?.copyWith(
                color: onContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onAccent,
    this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color onAccent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tokens = _CommunityTokens.of(context);
    final cs = Theme.of(context).colorScheme;
    final tint = Color.alphaBlend(accent.withOpacity(0.10), tokens.cardSurface);

    return Card(
      elevation: 0,
      color: tokens.cardSurface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tokens.cardBorder, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tokens.cardSurface, tint],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  button: true,
                  label: title,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withOpacity(0.10),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: onAccent, size: 26),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tokens.title,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.subtitle,
                    fontSize: 12,
                    height: 1.15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
