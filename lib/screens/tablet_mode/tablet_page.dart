import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 분리한 좌/우 패널
import '../../models/plate_model.dart';
import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../tablet_mode/body_panels/tablet_left_panel.dart';
import '../tablet_mode/body_panels/tablet_right_panel.dart';
import '../tablet_mode/widgets/tablet_top_navigation.dart';
import '../tablet_mode/states/tablet_pad_mode_state.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ 로고(PNG) 가독성 보장 유틸
/// - 단색/검정 고정 PNG 로고가 다크/브랜드 배경에서 안 보이는 문제 방지
/// - scaffoldBackgroundColor 기준으로 대비 계산 후 tint / 폴백
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

/// ✅ (경고 방지) required 파라미터만 사용하는 tint 로고 위젯
/// - BlendMode.srcIn: 원본 RGB 버리고 알파만 유지한 채 tint 적용
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

class TabletPage extends StatefulWidget {
  const TabletPage({super.key});

  @override
  State<TabletPage> createState() => _TabletPageState();
}

class _TabletPageState extends State<TabletPage> {
  StreamSubscription<PlateModel>? _removedSub;

  final List<String> _completedChips = <String>[];
  final Set<String> _completedChipSet = <String>{};
  final Set<String> _selectedChips = <String>{};
  String? _areaCache;

  // ✅ 하단 로고 크기(여기만 바꾸면 크기 조절)
  static const double _kBottomLogoHeight = 44.0;

  void _addCompletedChip(String plateNumber) {
    if (_completedChipSet.add(plateNumber)) {
      setState(() => _completedChips.insert(0, plateNumber));
    }
  }

  void _removeCompletedChip(String plateNumber) {
    if (_completedChipSet.remove(plateNumber)) {
      setState(() {
        _completedChips.remove(plateNumber);
        _selectedChips.remove(plateNumber);
      });
    }
  }

  void _toggleChipSelection(String plateNumber) {
    setState(() {
      if (_selectedChips.contains(plateNumber)) {
        _selectedChips.remove(plateNumber);
      } else {
        _selectedChips.add(plateNumber);
      }
    });
  }

  void _clearChipsForAreaChange() {
    setState(() {
      _completedChips.clear();
      _completedChipSet.clear();
      _selectedChips.clear();
    });
  }

  // 브랜드 테마(ColorScheme) 기반으로 SnackBar 스타일링
  SnackBar _styledSnackBar(BuildContext context, String message, {Duration? duration}) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SnackBar(
      content: Text(
        message,
        style: (text.bodyMedium ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onInverseSurface,
        ),
      ),
      behavior: SnackBarBehavior.floating,
      duration: duration ?? const Duration(seconds: 3),
      backgroundColor: cs.inverseSurface.withOpacity(.96),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      elevation: 0,
    );
  }

  @override
  void initState() {
    super.initState();

    // 구독 등록은 build 컨텍스트 사용이 필요하므로 post frame에서 수행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final plateState = context.read<PlateState>();
      final areaState = context.read<AreaState>();

      _removedSub = plateState.onDepartureRequestRemoved.listen((removed) {
        final currentArea = areaState.currentArea;
        if (!mounted || removed.area != currentArea) return;

        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          _styledSnackBar(context, '출차 완료 처리됨: ${removed.plateNumber}'),
        );

        _addCompletedChip(removed.plateNumber);
      });
    });
  }

  @override
  void dispose() {
    _removedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final area = context.select<AreaState, String?>((s) => s.currentArea) ?? '';
    final padMode = context.select<TabletPadModeState, PadMode>((s) => s.mode);

    // 지역 변경 시: 완료 칩 상태 초기화(기존 로직 유지)
    if (_areaCache != area) {
      _areaCache = area;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clearChipsForAreaChange();
      });
    }

    // ✅ 뒤로가기(시스템 back)로 이 라우트를 pop하지 않음 → 앱이 종료되지 않음
    return PopScope(
      canPop: false, // 루트 pop 차단
      onPopInvoked: (didPop) {
        if (didPop) return;

        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          _styledSnackBar(
            context,
            '뒤로가기가 비활성화되어 앱이 종료되지 않습니다. 상단 메뉴에서 이동하세요.',
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        // ✅ 고정 white 제거 → 브랜드 테마 surface를 배경으로
        backgroundColor: cs.surface,

        appBar: const PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight),
          child: SafeArea(
            bottom: false,
            child: TabletTopNavigation(isAreaSelectable: true),
          ),
        ),

        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _StickyNoticeBar(
                plates: _completedChips,
                selectedPlates: _selectedChips,
                onToggleSelect: _toggleChipSelection,
                onRemove: _removeCompletedChip,
              ),

              Expanded(
                child: padMode == PadMode.show
                // ▶ show 모드: 왼쪽 패널만 전체 화면
                    ? ColoredBox(
                  color: cs.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _PanelCard(
                      child: LeftPaneDeparturePlates(
                        key: ValueKey('left-pane-$area-show'),
                      ),
                    ),
                  ),
                )
                    : padMode == PadMode.mobile
                // ✅ mobile 모드: 좌/우 패널 분할 없이 단일 화면(검색+입력표시+키패드)
                    ? ColoredBox(
                  color: cs.surface,
                  child: RightPaneSearchPanel(
                    key: ValueKey('mobile-pane-$area'),
                    area: area,
                  ),
                )
                // ▶ big/small: 2열 유지 (small은 우측 패널 내부에서 키패드 100%)
                    : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ⬅️ 왼쪽 패널
                    Expanded(
                      child: ColoredBox(
                        color: cs.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: _PanelCard(
                            child: LeftPaneDeparturePlates(
                              key: ValueKey('left-pane-$area'),
                            ),
                          ),
                        ),
                      ),
                    ),

                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: cs.outlineVariant,
                    ),

                    // ➡️ 오른쪽 패널
                    Expanded(
                      child: ColoredBox(
                        color: cs.surface,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                          ),
                          child: RightPaneSearchPanel(
                            key: ValueKey('right-pane-$area'),
                            area: area,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.9))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: SizedBox(
                    height: _kBottomLogoHeight,
                    // ✅ (변경) 하단 텍스트 로고 tint 적용 + 대비 부족 시 폴백
                    child: _BrandTintedLogo(
                      assetPath: 'assets/images/ParkinWorkin_text.png',
                      height: _kBottomLogoHeight,
                      preferredColor: cs.primary,
                      fallbackColor: cs.onBackground,
                      minContrast: 3.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 패널 내부를 카드로 정리(라운드/보더/그림자)
class _PanelCard extends StatelessWidget {
  final Widget child;

  const _PanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        // ✅ 고정 white 제거 → surface 사용
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withOpacity(.12)),
        boxShadow: [
          BoxShadow(
            // ✅ Colors.black 제거 → scheme shadow 사용
            color: cs.shadow.withOpacity(.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
class _StickyNoticeBar extends StatelessWidget {
  final List<String> plates;
  final Set<String> selectedPlates;
  final void Function(String plateNumber) onToggleSelect;
  final void Function(String plateNumber) onRemove;

  const _StickyNoticeBar({
    required this.plates,
    required this.selectedPlates,
    required this.onToggleSelect,
    required this.onRemove,
  });

  Color _tintOnSurface(ColorScheme cs, {required double opacity}) {
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  @override
  Widget build(BuildContext context) {
    final hasChips = plates.isNotEmpty;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // ✅ 기존 "Deep Blue" 고정 팔레트 제거 → 브랜드 primary를 surface 위에 얇게 얹는 방식으로 톤 유지
    final dark = cs.brightness == Brightness.dark;
    final barBg = _tintOnSurface(cs, opacity: dark ? 0.14 : 0.06);
    final barBorder = cs.primary.withOpacity(dark ? 0.35 : 0.20);

    final infoIconColor = hasChips ? cs.tertiary : cs.primary;
    final titleColor = cs.onSurface;
    final bodyColor = cs.onSurface.withOpacity(.85);

    return Material(
      color: barBg,
      borderOnForeground: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: barBorder)),
        ),
        child: Row(
          children: [
            Icon(
              hasChips ? Icons.check_circle_outline : Icons.info_outline,
              size: 18,
              color: infoIconColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: hasChips
                  ? Row(
                children: [
                  Text(
                    '출차 완료:',
                    style: (text.bodySmall ?? const TextStyle()).copyWith(
                      fontSize: 13,
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: plates.map((p) {
                          final selected = selectedPlates.contains(p);

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InputChip(
                              label: Text(
                                p,
                                style: (text.labelMedium ?? const TextStyle()).copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: selected ? cs.onPrimary : cs.onSurface,
                                ),
                              ),
                              selected: selected,
                              showCheckmark: false,
                              onSelected: (_) => onToggleSelect(p),
                              onDeleted: selected ? () => onRemove(p) : null,
                              deleteIcon: selected
                                  ? Icon(Icons.close, size: 16, color: cs.onPrimary)
                                  : null,
                              backgroundColor: cs.surface,
                              selectedColor: cs.primary,
                              side: BorderSide(
                                color: selected ? cs.primary : cs.outline.withOpacity(.18),
                              ),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              )
                  : Text(
                '출차 요청 목록에서 방금 누른 번호가 사라졌다면, 출차 완료 처리된 것입니다.',
                style: (text.bodySmall ?? const TextStyle()).copyWith(
                  fontSize: 13,
                  color: bodyColor,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
