import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

class PlateCustomBoxStyles {
  static const Color base = Color(0xFF0D47A1);
  static const Color dark = Color(0xFF09367D);
  static const Color light = Color(0xFF5472D3);

  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
        fontWeight: FontWeight.w900,
        color: dark,
        letterSpacing: .1,
        height: 1.1,
      );

  static TextStyle subtitle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
        color: Theme.of(context).colorScheme.outline,
        height: 1.2,
      );

  static TextStyle value(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: dark.withOpacity(.92),
        height: 1.15,
      );

  static TextStyle valueMono(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontFamilyFallback: const ['monospace'],
        fontFeatures: const [FontFeature.tabularFigures()],
        color: dark.withOpacity(.92),
        height: 1.15,
      );

  static TextStyle label(BuildContext context, Color color) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(
        color: color,
        fontWeight: FontWeight.w900,
        letterSpacing: .1,
        height: 1.0,
      );
}

/// 컨테이너/그리드 방식 폐기 → "위에서 아래로 열거" 리스트 방식
/// + 필드명/필드값 정렬 고정(좌측 블록 고정폭)
class PlateCustomBox extends StatelessWidget {
  final String topLeftText; // 라벨(보통 '소속')
  final String topCenterText; // 메인 타이틀(지역+번호판)
  final String topRightUpText; // 정산 타입
  final String topRightDownText; // 요금

  final String midLeftText; // 위치
  final String midCenterText; // 사용자
  final String midRightText; // 시각

  final String bottomLeftLeftText; // 상태 리스트 문자열
  final String bottomLeftCenterText; // customStatus
  final String bottomRightText; // 경과

  final VoidCallback onTap;
  final bool isSelected;
  final Color? backgroundColor;

  const PlateCustomBox({
    super.key,
    required this.topLeftText,
    required this.topCenterText,
    required this.topRightUpText,
    required this.topRightDownText,
    required this.midLeftText,
    required this.midCenterText,
    required this.midRightText,
    required this.bottomLeftLeftText,
    required this.bottomLeftCenterText,
    required this.bottomRightText,
    required this.onTap,
    required this.isSelected,
    this.backgroundColor,
  });

  String get _statusCombined {
    final a = bottomLeftLeftText.trim();
    final b = bottomLeftCenterText.trim();
    if (a.isEmpty && b.isEmpty) return '';
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a · $b';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final baseBg = backgroundColor ?? PlateCustomBoxStyles.base.withOpacity(.03);
    final bg = isSelected ? PlateCustomBoxStyles.base.withOpacity(.07) : baseBg;

    final borderColor = isSelected
        ? PlateCustomBoxStyles.base.withOpacity(.35)
        : PlateCustomBoxStyles.light.withOpacity(.22);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: PlateCustomBoxStyles.base.withOpacity(.14),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderLine(
                title: topCenterText,
                billingType: topRightUpText,
                feeText: topRightDownText,
              ),
              const SizedBox(height: 10),

              // 칩 영역: 1줄 고정 + 가로 스크롤
              SizedBox(
                height: 30,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _Chip(
                        icon: Icons.apartment_outlined,
                        label:
                        topLeftText.trim().isEmpty ? '소속' : topLeftText.trim(),
                        tone: _ChipTone.neutral,
                      ),
                      const SizedBox(width: 8),
                      if (isSelected)
                        _Chip(
                          icon: Icons.check_circle_outline,
                          label: '선택됨',
                          tone: _ChipTone.selected,
                        ),
                      const SizedBox(width: 8),
                      _Chip(
                        icon: Icons.receipt_long_outlined,
                        label: topRightUpText.trim().isEmpty
                            ? '없음'
                            : topRightUpText.trim(),
                        tone: _ChipTone.primary,
                        maxWidth: 180,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Divider(height: 1, color: cs.outline.withOpacity(.15)),
              const SizedBox(height: 12),

              // ✅ 필드명/필드값 정렬 고정(좌측 블록 고정 폭)
              _AlignedFieldRow(
                icon: Icons.place_outlined,
                label: '주차구역',
                value: midLeftText.trim().isEmpty ? '미지정' : midLeftText.trim(),
                tone: _Tone.location,
              ),
              const SizedBox(height: 10),

              _AlignedFieldRow(
                icon: Icons.person_outline,
                label: '사용자',
                value: midCenterText.trim().isEmpty ? '-' : midCenterText.trim(),
                tone: _Tone.user,
              ),
              const SizedBox(height: 10),

              _AlignedFieldRow(
                icon: Icons.schedule_outlined,
                label: '시각',
                value: midRightText.trim().isEmpty ? '-' : midRightText.trim(),
                tone: _Tone.time,
                mono: true,
              ),
              const SizedBox(height: 10),

              _AlignedFieldRow(
                icon: Icons.timelapse_outlined,
                label: '경과',
                value: bottomRightText.trim().isEmpty ? '-' : bottomRightText.trim(),
                tone: _Tone.elapsed,
              ),
              const SizedBox(height: 10),

              _AlignedFieldRow(
                icon: Icons.info_outline,
                label: '상태',
                value: _statusCombined.isEmpty ? '표시할 상태가 없습니다.' : _statusCombined,
                tone: _Tone.status,
                // 상태도 정렬 안정성을 위해 1줄 고정(필요 시 Tooltip로 전체 확인)
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────
/// Header
/// ─────────────────────────────────────────────────────────

class _HeaderLine extends StatelessWidget {
  final String title;
  final String billingType;
  final String feeText;

  const _HeaderLine({
    required this.title,
    required this.billingType,
    required this.feeText,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title.trim().isEmpty ? '-' : title.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: PlateCustomBoxStyles.title(context),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              billingType.trim().isEmpty ? '없음' : billingType.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: PlateCustomBoxStyles.label(
                context,
                PlateCustomBoxStyles.base,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                feeText.trim().isEmpty ? '-' : feeText.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: PlateCustomBoxStyles.base,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────
/// Aligned Field Rows (정렬 고정 핵심)
/// ─────────────────────────────────────────────────────────

enum _Tone { location, user, time, elapsed, status }

class _TonePalette {
  final Color tint;
  final Color icon;
  final Color label;

  const _TonePalette({
    required this.tint,
    required this.icon,
    required this.label,
  });

  static _TonePalette of(_Tone t) {
    switch (t) {
      case _Tone.location:
        return _TonePalette(
          tint: Colors.teal.withOpacity(.06),
          icon: Colors.teal.shade700,
          label: Colors.teal.shade800,
        );
      case _Tone.user:
        return _TonePalette(
          tint: Colors.indigo.withOpacity(.06),
          icon: Colors.indigo.shade700,
          label: Colors.indigo.shade800,
        );
      case _Tone.time:
        return _TonePalette(
          tint: PlateCustomBoxStyles.base.withOpacity(.06),
          icon: PlateCustomBoxStyles.base,
          label: PlateCustomBoxStyles.base,
        );
      case _Tone.elapsed:
        return _TonePalette(
          tint: Colors.red.withOpacity(.06),
          icon: Colors.red.shade700,
          label: Colors.red.shade800,
        );
      case _Tone.status:
      return _TonePalette(
          tint: Colors.grey.withOpacity(.06),
          icon: Colors.grey.shade700,
          label: Colors.grey.shade800,
        );
    }
  }
}

class _AlignedFieldRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final _Tone tone;
  final bool mono;
  final int maxLines;

  const _AlignedFieldRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    this.mono = false,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = _TonePalette.of(tone);

    // ✅ 정렬 고정 핵심 파라미터
    // - 모든 행에서 "값"이 시작되는 X좌표를 동일하게 유지
    const double leftBlockWidth = 120; // 아이콘 + 간격 + 라벨 영역 전체 폭
    const double rowHeight = 42; // 값 영역 높이(레이아웃 안정)

    final valueStyle = mono
        ? PlateCustomBoxStyles.valueMono(context)
        : PlateCustomBoxStyles.value(context);

    final safeValue = value.trim().isEmpty ? '-' : value.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ✅ 좌측 블록(아이콘+라벨) 고정 폭
        SizedBox(
          width: leftBlockWidth,
          child: Row(
            children: [
              Icon(icon, size: 18, color: p.icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: PlateCustomBoxStyles.label(context, p.label),
                ),
              ),
            ],
          ),
        ),

        // ✅ 우측 값 영역: 모든 행 동일 시작점 + 동일 높이
        Expanded(
          child: Tooltip(
            message: safeValue,
            waitDuration: const Duration(milliseconds: 450),
            child: Container(
              height: rowHeight,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: p.tint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outline.withOpacity(.12)),
              ),
              child: Text(
                safeValue,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: valueStyle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────
/// Chips
/// ─────────────────────────────────────────────────────────

enum _ChipTone { primary, neutral, selected, warn }

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final _ChipTone tone;
  final double? maxWidth;

  const _Chip({
    required this.icon,
    required this.label,
    required this.tone,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    Color bg;
    Color fg;
    Color bd;

    switch (tone) {
      case _ChipTone.primary:
        bg = PlateCustomBoxStyles.base.withOpacity(.08);
        fg = PlateCustomBoxStyles.base;
        bd = PlateCustomBoxStyles.light.withOpacity(.25);
        break;
      case _ChipTone.selected:
        bg = Colors.teal.withOpacity(.10);
        fg = Colors.teal.shade800;
        bd = Colors.teal.withOpacity(.25);
        break;
      case _ChipTone.warn:
        bg = Colors.orange.withOpacity(.12);
        fg = Colors.orange.shade800;
        bd = Colors.orange.withOpacity(.25);
        break;
      case _ChipTone.neutral:
        bg = Colors.black.withOpacity(.04);
        fg = PlateCustomBoxStyles.dark.withOpacity(.85);
        bd = Colors.black.withOpacity(.08);
        break;
    }

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label.trim().isEmpty ? '-' : label.trim(),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            softWrap: false,
            style: text.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w900,
              letterSpacing: .1,
              height: 1.0,
            ),
          ),
        ),
      ],
    );

    return Container(
      constraints: maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth!),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bd),
      ),
      child: child,
    );
  }
}
