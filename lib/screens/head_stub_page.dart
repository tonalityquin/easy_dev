// lib/screens/head_stub_page.dart
import 'dart:io'; // ⬅️ 파일 경로 열기 대비(에셋 사용 시에도 무해)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart'; // ⬅️ PDF 뷰어

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

// ✅ (신규) 본사 허브 퀵 액션 버블 ON/OFF 제어를 위해 import
import 'head_package/hub_quick_actions.dart';

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

                      // ✅ HR(관리) — Blue (누락됐던 상수 추가)
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
                            LaborGuidePage.showAsBottomSheet(context);
                          },
                        ),

                        // ▼ 출/퇴근 → 출석 캘린더: ✅ “바텀시트(92%)”로 열기
                        _ActionCard(
                          icon: Icons.how_to_reg_rounded,
                          title: '출/퇴근',
                          subtitle: 'Spread Sheets',
                          bg: hrBase,
                          fg: Colors.white,
                          tintColor: hrLight,
                          titleColor: hrDark,
                          onTap: () {
                            hr_att.AttendanceCalendar.showAsBottomSheet(context);
                          },
                        ),

                        // ▼ 휴게 관리 → 휴식 캘린더(BreakCalendar) : ✅ 바텀시트(92%)로 열기
                        _ActionCard(
                          icon: Icons.free_breakfast_rounded,
                          title: '휴게 관리',
                          subtitle: 'Spread Sheets',
                          bg: attBase,
                          fg: Colors.white,
                          tintColor: attLight,
                          titleColor: attDark,
                          onTap: () {
                            hr_break.BreakCalendar.showAsBottomSheet(context);
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

                        // ▼ (신규) 튜토리얼
                        _ActionCard(
                          icon: Icons.menu_book_rounded,
                          title: '튜토리얼',
                          subtitle: 'PDF 가이드 모음',
                          bg: const Color(0xFF00695C),
                          fg: Colors.white,
                          tintColor: const Color(0xFF80CBC4),
                          titleColor: const Color(0xFF004D40),
                          onTap: () async {
                            final selected = await showModalBottomSheet<TutorialItem>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => TutorialPickerBottomSheet(
                                items: const [
                                  TutorialItem(
                                    title: '00.basic',
                                    assetPath: 'assets/00.basic.pdf', // ⬅️ 사용 중인 에셋 경로
                                  ),
                                  // 추후 확장: TutorialItem(title: '01.advanced', assetPath: 'assets/01.advanced.pdf'),
                                ],
                              ),
                            );

                            if (selected != null) {
                              // 바텀시트 닫힌 뒤 푸시
                              await TutorialPdfViewer.open(context, selected);
                            }
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
    final cs = Theme.of(context).colorScheme;

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

          // 🔘 ON/OFF 토글 — 오른쪽에 고정 (HeadHubActions 버블)
          ValueListenableBuilder<bool>(
            valueListenable: HeadHubActions.enabled,
            builder: (context, on, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: on ? _dark.withOpacity(.12) : cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: on ? _dark.withOpacity(.35) : cs.outlineVariant,
                      ),
                    ),
                    child: Text(
                      on ? 'Bubble ON' : 'Bubble OFF',
                      style: text.labelMedium?.copyWith(
                        color: on ? _dark : cs.outline,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: on,
                    onChanged: (v) async {
                      HeadHubActions.setEnabled(v);
                      if (v) {
                        // 켜질 때 바로 부착 시도
                        await HeadHubActions.mountIfNeeded();
                      }
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(v
                              ? '본사 허브 버블이 켜졌습니다.'
                              : '본사 허브 버블이 꺼졌습니다.'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(milliseconds: 900),
                        ),
                      );
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
          // ✅ 반드시 이름 있는 인자 사용
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

/// ─────────────────────────────────────────────────────────────────
/// 튜토리얼: 아이템 / 바텀시트 / PDF 뷰어
/// ─────────────────────────────────────────────────────────────────

class TutorialItem {
  final String title;
  final String? assetPath; // 예: assets/00.basic.pdf
  final String? filePath;  // 예: /storage/emulated/0/Download/00.basic.pdf

  const TutorialItem({
    required this.title,
    this.assetPath,
    this.filePath,
  });
}

class TutorialPickerBottomSheet extends StatelessWidget {
  final List<TutorialItem> items;
  const TutorialPickerBottomSheet({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (_, controller) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: cs.outlineVariant.withOpacity(.35)),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withOpacity(.06),
                  blurRadius: 20,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withOpacity(.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                const ListTile(
                  title: Text('튜토리얼', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('읽을 항목을 선택하세요'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return ListTile(
                        leading: const Icon(Icons.picture_as_pdf_rounded),
                        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          item.assetPath != null ? '앱 에셋' : '로컬 파일',
                          style: TextStyle(color: cs.outline),
                        ),
                        onTap: () => Navigator.of(context).pop(item),
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: items.length,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TutorialPdfViewer extends StatefulWidget {
  final String title;
  final PdfControllerPinch controller;

  const TutorialPdfViewer({
    super.key,
    required this.title,
    required this.controller,
  });

  /// 선택한 튜토리얼을 열기 위한 헬퍼
  static Future<void> open(BuildContext context, TutorialItem item) async {
    // ✅ pdfx(2.9.x) 규격에 맞게 Future<PdfDocument>를 준비
    Future<PdfDocument> futureDoc;

    if (item.assetPath != null) {
      futureDoc = PdfDocument.openAsset(item.assetPath!);
    } else if (item.filePath != null) {
      // 파일 경로가 실제 존재하는지 간단 체크
      if (!File(item.filePath!).existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF 파일을 찾을 수 없습니다.')),
        );
        return;
      }
      futureDoc = PdfDocument.openFile(item.filePath!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('열 수 있는 PDF 경로가 없습니다.')),
      );
      return;
    }

    // ✅ Future<PdfDocument>를 그대로 주입
    final controller = PdfControllerPinch(document: futureDoc);

    // 전체 화면으로 푸시
    // (iOS/Android 공통, 뒤로가기 시 컨트롤러/문서 자동 정리)
    // ignore: use_build_context_synchronously
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TutorialPdfViewer(title: item.title, controller: controller),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<TutorialPdfViewer> createState() => _TutorialPdfViewerState();
}

class _TutorialPdfViewerState extends State<TutorialPdfViewer> {
  @override
  void dispose() {
    // ✅ 메모리 정리
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '첫 페이지',
            icon: const Icon(Icons.first_page_rounded),
            // ✅ 위치 인자 사용 (이름있는 인자 ❌)
            onPressed: () => widget.controller.jumpToPage(1),
          ),
        ],
      ),
      body: Container(
        color: cs.surface,
        child: PdfViewPinch(
          controller: widget.controller,
          onDocumentError: (e) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('PDF 오류: $e')));
          },
        ),
      ),
    );
  }
}
