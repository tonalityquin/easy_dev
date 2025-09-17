// lib/screens/head_stub_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../routes.dart';
import 'head_package/head_memo.dart';
import 'head_package/roadmap_bottom_sheet.dart'; // 커뮤니티 폴더의 바텀시트를 재사용

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

                    // Attendance Sheet — Indigo
                    const attBase = Color(0xFF3949AB);
                    const attDark = Color(0xFF283593);
                    const attLight = Color(0xFF7986CB);

                    final cards = <Widget>[
                      _ActionCard(
                        icon: Icons.calendar_month_rounded,
                        title: '회사 달력',
                        subtitle: 'Google Calendar\nGoogle Sheets',
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

                      // ▼ 로드맵 (커뮤니티 → 본사 허브로 이동)
                      _ActionCard(
                        icon: Icons.edit_note_rounded,
                        title: '향후 로드맵',
                        subtitle: 'After Release',
                        bg: cs.tertiaryContainer,
                        fg: cs.onTertiaryContainer,
                        tintColor: attLight.withOpacity(0.45), // 살짝 하이라이트
                        titleColor: attDark,
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const RoadmapBottomSheet(),
                          );
                        },
                      ),

                      // ▼ 신규: 출/퇴근(시트 뷰)
                      _ActionCard(
                        icon: Icons.schedule_rounded,
                        title: '출/퇴근',
                        subtitle: 'Google Sheets',
                        bg: attBase,
                        fg: Colors.white,
                        tintColor: attLight,
                        titleColor: attDark,
                        onTap: () {
                          Navigator.of(context).pushNamed(AppRoutes.attendanceSheet);
                        },
                      ),
                      _ActionCard(
                        icon: Icons.sticky_note_2_rounded,
                        title: '메모',
                        subtitle: '플로팅 버블 · 어디서나 기록',
                        bg: cs.primaryContainer,
                        fg: cs.onPrimaryContainer,
                        tintColor: calLight.withOpacity(0.45),
                        titleColor: calDark,
                        onTap: () async {
                          // 카드에서는 온오프를 건드리지 않음. 패널에서 스위치로 제어.
                          await HeadMemo.openPanel();
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
              color: _dark.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_rounded, color: _dark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '본사 허브 입니다.',
              style: text.bodyMedium?.copyWith(
                color: _dark,
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
    );
  }
}
