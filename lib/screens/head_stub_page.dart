import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../routes.dart';

class HeadStubPage extends StatelessWidget {
  const HeadStubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: Text(
          '본사 허브',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: cs.onSurface,
          ),
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
        actionsIconTheme: IconThemeData(color: cs.onSurface),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
      ),
      body: SafeArea(
        child: Container(
          color: Colors.white,
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeaderBanner(),
              const SizedBox(height: 16),

              // ✅ 반응형 Grid: 화면 너비/텍스트배율에 따라 열 수와 타일 비율 계산
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
                    final textScale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);

                    final tileWidth = (width - spacing * (crossAxisCount - 1)) / crossAxisCount;

                    // 타일 기준 높이(컨텐츠에 여유), 텍스트 배율 반영
                    final baseTileHeight = 150.0;
                    final tileHeight = baseTileHeight * textScale;
                    final childAspectRatio = tileWidth / tileHeight;

                    // ── 팔레트 정의 (base/dark/light) ─────────────────────────

                    // Company Calendar — Green
                    const calBase = Color(0xFF43A047);
                    const calDark = Color(0xFF2E7D32);
                    const calLight = Color(0xFFA5D6A7);

                    // Labor Guide — Orange/Amber
                    const laborBase = Color(0xFFF57C00);
                    const laborDark = Color(0xFFE65100);
                    const laborLight = Color(0xFFFFCC80);

                    final cards = <Widget>[
                      _ActionCard(
                        icon: Icons.calendar_month_rounded,
                        title: '회사 달력',
                        subtitle: 'Google Calendar\nGoogle Sheet',
                        // ✅ 2줄
                        bg: calBase,
                        fg: Colors.white,
                        tintColor: calLight,
                        titleColor: calDark,
                        onTap: () {
                          Navigator.of(context).pushNamed(AppRoutes.companyCalendar);
                        },
                      ),
                      _ActionCard(
                        icon: Icons.gavel_rounded,
                        title: '회사 노무',
                        subtitle: 'Google Drive',
                        bg: laborBase,
                        fg: Colors.white,
                        tintColor: laborLight,
                        titleColor: laborDark,
                        onTap: () {
                          Navigator.of(context).pushNamed(AppRoutes.laborGuide);
                        },
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

              Center(
                child: InkWell(
                  onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                    '/selector', // AppRoutes.selector
                    (route) => false,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 80,
                    child: Image.asset('assets/images/pelican.png'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  // 본사 카드 팔레트(고정값)
  static const Color _base = Color(0xFF1E88E5); // 배너 테두리 틴트
  static const Color _dark = Color(0xFF1565C0); // 텍스트/아이콘
  static const Color _light = Color(0xFF64B5F6); // 배경 계열

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 단색을 원하면: color: _light.withOpacity(0.7),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _light.withOpacity(0.95),
            _light.withOpacity(0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _base.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _dark.withOpacity(0.08), // 아이콘 배경 원형
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_rounded, color: _dark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '본사 허브 입니다.',
              style: text.bodyMedium?.copyWith(
                color: _dark, // 텍스트 컬러 고정
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color bg; // 배지 배경(base)
  final Color fg; // 배지 아이콘(onBase)
  final Color? tintColor; // 카드 surfaceTint(light)
  final Color? titleColor; // 제목 색(dark)
  final VoidCallback? onTap; // 카드 아무 곳이나 탭

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bg,
    required this.fg,
    this.tintColor,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: tintColor ?? bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // 살짝 여백 절약
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: fg, size: 26),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: titleColor ?? Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  height: 1.15, // 줄간격을 살짝 촘촘하게
                ),
                maxLines: 2,
                // 최대 2줄
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
