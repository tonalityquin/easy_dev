import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/discord/discord_config.dart';
import '../application/game/game_quick_actions.dart';
import 'sheets/discord/discord_bottom_sheet.dart';

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

class CommunityStubPage extends StatelessWidget {
  const CommunityStubPage({super.key});

  static const String _termsOfServiceUrl =
      'https://sites.google.com/view/parkinworkin3/%ED%99%88';
  static const String _privacyPolicyUrl =
      'https://sites.google.com/view/parkinworkin4/%ED%99%88';
  static const String _contactFormUrl = 'https://forms.gle/nbwaFeLhJfAKAf6o8';

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

  Future<void> _openContactForm() async {
    await _openExternalPage(_contactFormUrl);
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
    await GameQuickActions.openTetrisSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final isShort = media.size.height < 640;
    final keyboardOpen = media.viewInsets.bottom > 0;
    final footerHeight = (isShort || keyboardOpen) ? 72.0 : 112.0;

    final actions = <_CommunityAction>[
      _CommunityAction(
        icon: Icons.mic_rounded,
        title: '사내 업무 커뮤니티',
        accent: cs.secondary,
        onAccent: cs.onSecondary,
        onTap: () => _openWalkieFlow(context),
        onLongPress: () => _openWalkieTutorial(context),
      ),
      _CommunityAction(
        icon: Icons.videogame_asset_rounded,
        title: '아케이드',
        accent: cs.secondary,
        onAccent: cs.onSecondary,
        onTap: () => _openArcadeSheet(context),
      ),
      _CommunityAction(
        icon: Icons.contact_support_rounded,
        title: '문의하기',
        accent: cs.primary,
        onAccent: cs.onPrimary,
        onTap: _openContactForm,
      ),
      _CommunityAction(
        icon: Icons.description_rounded,
        title: '이용약관',
        accent: cs.tertiary,
        onAccent: cs.onTertiary,
        onTap: _openTermsOfService,
      ),
      _CommunityAction(
        icon: Icons.privacy_tip_rounded,
        title: '개인정보보호처리방침',
        accent: cs.primaryContainer,
        onAccent: cs.onPrimaryContainer,
        onTap: _openPrivacyPolicy,
      ),
    ];

    return Scaffold(
      backgroundColor: cs.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: _CommunityHeader(
                  title: '커뮤니티 허브',
                  actionCount: actions.length,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                  children: [
                    _CommunityMetricRow(
                      actions: actions.length,
                    ),
                    const SizedBox(height: 12),
                    _GameControlPanel(),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final crossAxisCount = width >= 980
                            ? 4
                            : width >= 680
                                ? 3
                                : 2;
                        const spacing = 10.0;
                        final tileWidth =
                            (width - spacing * (crossAxisCount - 1)) /
                                crossAxisCount;
                        const tileHeight = 124.0;
                        return GridView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: spacing,
                            crossAxisSpacing: spacing,
                            childAspectRatio: tileWidth / tileHeight,
                          ),
                          itemCount: actions.length,
                          itemBuilder: (context, i) =>
                              _CommunityActionTile(action: actions[i]),
                        );
                      },
                    ),
                  ],
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
              color: cs.background,
              border: Border(
                top: BorderSide(color: cs.outlineVariant.withOpacity(.65)),
              ),
            ),
            child: SizedBox(
              height: footerHeight,
              child: Center(
                child: _BrandTintedLogo(height: footerHeight),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityHeader extends StatelessWidget {
  const _CommunityHeader({
    required this.title,
    required this.actionCount,
    required this.onBack,
  });

  final String title;
  final int actionCount;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: '뒤로가기',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 8),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.secondary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.forum_rounded, color: cs.onSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (tt.titleLarge ?? const TextStyle(fontSize: 20)).copyWith(
                color: cs.onInverseSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: -.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _HeaderCountPill(
            icon: Icons.apps_rounded,
            label: '$actionCount',
          ),
        ],
      ),
    );
  }
}

class _HeaderCountPill extends StatelessWidget {
  const _HeaderCountPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: cs.onInverseSurface.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.onInverseSurface.withOpacity(.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.onInverseSurface),
          const SizedBox(width: 6),
          Text(
            label,
            style: (tt.labelMedium ?? const TextStyle(fontSize: 12)).copyWith(
              color: cs.onInverseSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityMetricRow extends StatelessWidget {
  const _CommunityMetricRow({required this.actions});

  final int actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _MetricChip(
            icon: Icons.apps_rounded,
            label: '기능',
            value: '$actions',
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: GameQuickActions.enabled,
            builder: (context, on, _) {
              return _MetricChip(
                icon: on ? Icons.bolt_rounded : Icons.power_settings_new_rounded,
                label: '게임',
                value: on ? 'ON' : 'OFF',
                color: on ? cs.secondary : cs.onSurfaceVariant,
              );
            },
          ),
          const SizedBox(width: 8),
          _MetricChip(
            icon: Icons.open_in_new_rounded,
            label: '외부',
            value: '3',
            color: cs.tertiary,
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(.10), cs.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: (tt.labelMedium ?? const TextStyle(fontSize: 12)).copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: (tt.titleSmall ?? const TextStyle(fontSize: 14)).copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _GameControlPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.sports_esports_rounded, color: cs.onSecondaryContainer),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '게임 퀵버블',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (tt.titleSmall ?? const TextStyle(fontSize: 15)).copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: GameQuickActions.enabled,
            builder: (context, on, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusPill(
                    label: on ? 'ON' : 'OFF',
                    color: on ? cs.secondary : cs.onSurfaceVariant,
                  ),
                  Switch.adaptive(
                    value: on,
                    onChanged: (v) async {
                      GameQuickActions.setEnabled(v);
                      if (v) await GameQuickActions.mountIfNeeded();
                      HapticFeedback.selectionClick();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(v ? '게임 퀵버블 ON' : '게임 퀵버블 OFF'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(milliseconds: 900),
                          ),
                        );
                      }
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(.10), cs.surface),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _CommunityAction {
  const _CommunityAction({
    required this.icon,
    required this.title,
    required this.accent,
    required this.onAccent,
    this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final Color onAccent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
}

class _CommunityActionTile extends StatelessWidget {
  const _CommunityActionTile({required this.action});

  final _CommunityAction action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        onLongPress: action.onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: action.accent,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(action.icon, color: action.onAccent, size: 22),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                ],
              ),
              const Spacer(),
              Text(
                action.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: (tt.titleSmall ?? const TextStyle(fontSize: 15)).copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
