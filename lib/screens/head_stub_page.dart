// lib/screens/head_stub_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../routes.dart';
import 'head_package/head_memo.dart';
import 'head_package/roadmap_bottom_sheet.dart';

// ▼ 근무지 현황
import 'head_package/mgmt_package/field.dart' as mgmt;

// ▼ 통계 비교
import 'head_package/mgmt_package/statistics.dart' as mgmt_stats;

// ▼ 출/퇴근(출석) · 휴게 관리
import 'head_package/hr_package/attendance_calendar.dart' as hr_att;
import 'head_package/hr_package/break_calendar.dart' as hr_break;

// ▼ (추가) 본사 달력 바텀시트로 열기 위한 import
import 'head_package/company_calendar_page.dart'; // ⬅️ 바텀시트 헬퍼 사용
// ▼ (추가) 회사 노무도 바텀시트로 열기 위한 import
import 'head_package/labor_guide_page.dart'; // ⬅️ 바텀시트 헬퍼 사용

class HeadStubPage extends StatelessWidget {
  const HeadStubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // ✅ 이 화면에서만 뒤로가기 pop을 막아 앱 종료 방지 (스낵바 없음)
    return PopScope(
      canPop: false,
      child: Scaffold(
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

                // ✅ 반응형 Grid
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

                      final tileWidth =
                          (width - spacing * (crossAxisCount - 1)) / crossAxisCount;
                      const baseTileHeight = 150.0;
                      final tileHeight = baseTileHeight * textScale;
                      final childAspectRatio = tileWidth / tileHeight;

                      // ── 팔레트 정의 ─────────────────────────
                      // Company Calendar — Green
                      const calBase = Color(0xFF43A047);
                      const calDark = Color(0xFF2E7D32);
                      const calLight = Color(0xFFA5D6A7);

                      // Labor Guide — Orange/Amber
                      const laborBase = Color(0xFFF57C00);
                      const laborDark = Color(0xFFE65100);
                      const laborLight = Color(0xFFFFCC80);

                      // Attendance Sheet(과거) — Indigo
                      const attBase = Color(0xFF3949AB);
                      const attDark = Color(0xFF283593);
                      const attLight = Color(0xFF7986CB);

                      // 근무지 현황 — Teal
                      const hubBase = Color(0xFF00897B); // teal 600
                      const hubDark = Color(0xFF00695C); // teal 800
                      const hubLight = Color(0xFF80CBC4); // teal 200

                      // 통계 비교 — Deep Purple
                      const statBase = Color(0xFF6A1B9A); // deep purple 700
                      const statDark = Color(0xFF4A148C); // deep purple 900
                      const statLight = Color(0xFFCE93D8); // deep purple 200

                      // HR(관리) — Blue
                      const hrBase = Color(0xFF1565C0); // blue 800
                      const hrDark = Color(0xFF0D47A1); // blue 900
                      const hrLight = Color(0xFF90CAF9); // blue 200

                      final cards = <Widget>[
                        _ActionCard(
                          icon: Icons.calendar_month_rounded,
                          title: '본사 달력',
                          subtitle: 'Google Calendar\nSpread Sheets',
                          bg: calBase,
                          fg: Colors.white,
                          tintColor: calLight,
                          titleColor: calDark,
                          onTap: () {
                            // ⬇️ 라우트 푸시 → "전체 화면 바텀시트"로 오픈
                            CompanyCalendarPage.showAsBottomSheet(context);
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
                            // ⬇️ 라우트 푸시 → "전체 화면 바텀시트"로 오픈
                            LaborGuidePage.showAsBottomSheet(context);
                          },
                        ),

                        // ▼ 출/퇴근 → 출석 캘린더(AttendanceCalendar)로 바로 이동
                        _ActionCard(
                          icon: Icons.how_to_reg_rounded,
                          title: '출/퇴근',
                          subtitle: 'Spread Sheets',
                          bg: hrBase,
                          fg: Colors.white,
                          tintColor: hrLight,
                          titleColor: hrDark,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const hr_att.AttendanceCalendar(),
                              ),
                            );
                          },
                        ),

                        // ▼ 휴게 관리 → 휴식 캘린더(BreakCalendar)
                        _ActionCard(
                          icon: Icons.free_breakfast_rounded,
                          title: '휴게 관리',
                          subtitle: 'Spread Sheets',
                          bg: attBase,
                          fg: Colors.white,
                          tintColor: attLight,
                          titleColor: attDark,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const hr_break.BreakCalendar(),
                              ),
                            );
                          },
                        ),

                        // ▼ 로드맵
                        _ActionCard(
                          icon: Icons.edit_note_rounded,
                          title: '향후 로드맵',
                          subtitle: 'After Release',
                          bg: cs.tertiaryContainer,
                          fg: cs.onTertiaryContainer,
                          tintColor: attLight.withOpacity(0.45),
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

                        // ▼ 메모
                        _ActionCard(
                          icon: Icons.sticky_note_2_rounded,
                          title: '메모',
                          subtitle: '플로팅 버블 · 어디서나 기록',
                          bg: cs.primaryContainer,
                          fg: cs.onPrimaryContainer,
                          tintColor: calLight.withOpacity(0.45),
                          titleColor: calDark,
                          onTap: () async {
                            await HeadMemo.openPanel();
                          },
                        ),

                        // ▼ 근무지 현황 (mgmt.Field로 이동)
                        _ActionCard(
                          icon: Icons.map_rounded,
                          title: '근무지 현황',
                          subtitle: 'Division별 지역 · 인원',
                          bg: hubBase,
                          fg: Colors.white,
                          tintColor: hubLight,
                          titleColor: hubDark,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const mgmt.Field(),
                              ),
                            );
                          },
                        ),

                        // ▼ 통계 비교 (mgmt_stats.Statistics로 이동)
                        _ActionCard(
                          icon: Icons.stacked_line_chart_rounded,
                          title: '통계 비교',
                          subtitle: '입·출차/정산 추이',
                          bg: statBase,
                          fg: Colors.white,
                          tintColor: statLight,
                          titleColor: statDark,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const mgmt_stats.Statistics(),
                              ),
                            );
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
                      AppRoutes.selector,
                          (route) => false,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 80,
                      child: Semantics(
                        label: '허브 선택 화면으로 돌아가기',
                        button: true,
                        child: Image.asset('assets/images/pelican.png'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        // ✅ 상호 이동 FAB 제거됨
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  static const Color _base = Color(0xFF1E88E5);
  static const Color _dark = Color(0xFF1565C0);
  static const Color _light = Color(0xFF64B5F6);

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
              '본사 허브입니다.',
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
  final Color bg;
  final Color fg;
  final Color? tintColor;
  final Color? titleColor;
  final VoidCallback? onTap;

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
              // 아이콘은 외곽 카드 탭에 제스처를 위임(스크린리더 중복 방지)
              Semantics(
                button: true,
                label: title,
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
