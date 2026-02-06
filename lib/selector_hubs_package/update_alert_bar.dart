import 'dart:convert';

import 'package:flutter/material.dart';

import '../screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

/// UpdateAlertBar 리팩터링 포인트
/// - 하드코딩 색상(Colors.transparent 등) 최소화: ColorScheme 기반 + 의미 토큰 사용
/// - 로그 상태 체크 중복 호출/레이스 방지: _refreshSeq 시퀀스 도입
/// - 로그 판별 로직을 분리: _detectErrorLogFromLines()
/// - 접근성: Semantics 유지 + Tooltip 일관성(필요 시)
@immutable
class _UpdateAlertTokens {
  const _UpdateAlertTokens({
    required this.updateBg,
    required this.updateFg,
    required this.logOkBg,
    required this.logOkFg,
    required this.logErrBg,
    required this.logErrFg,
    required this.inkOverlay,
  });

  final Color updateBg;
  final Color updateFg;

  final Color logOkBg;
  final Color logOkFg;

  final Color logErrBg;
  final Color logErrFg;

  /// InkWell overlay 대체(테마에 맞춘 미세 오버레이)
  final Color inkOverlay;

  factory _UpdateAlertTokens.of(BuildContext context, {Color? updateBg, Color? updateFg}) {
    final cs = Theme.of(context).colorScheme;

    return _UpdateAlertTokens(
      updateBg: updateBg ?? cs.primary,
      updateFg: updateFg ?? cs.onPrimary,
      logOkBg: cs.secondaryContainer,
      logOkFg: cs.onSecondaryContainer,
      logErrBg: cs.tertiaryContainer,
      logErrFg: cs.onTertiaryContainer,
      inkOverlay: cs.onSurface.withOpacity(0.06),
    );
  }
}

class UpdateAlertBar extends StatefulWidget {
  const UpdateAlertBar({
    super.key,
    required this.onTapUpdate,
    required this.onTapLogs,
    this.background,
    this.foreground,
  });

  final VoidCallback onTapUpdate;
  final VoidCallback onTapLogs;

  /// 업데이트 버튼 배경색(미지정 시 ColorScheme.primary)
  final Color? background;

  /// 업데이트 버튼 전경색(미지정 시 ColorScheme.onPrimary)
  final Color? foreground;

  @override
  State<UpdateAlertBar> createState() => _UpdateAlertBarState();
}

class _UpdateAlertBarState extends State<UpdateAlertBar> {
  bool _hasErrorLogs = false;

  /// 동시에 여러 refresh가 돌 때, 마지막 결과만 반영
  int _refreshSeq = 0;

  @override
  void initState() {
    super.initState();
    _refreshLogStatus();
  }

  Future<void> _refreshLogStatus() async {
    final int seq = ++_refreshSeq;

    try {
      final hasLogs = await _hasAnyErrorLog();
      if (!mounted) return;
      if (seq != _refreshSeq) return;

      setState(() => _hasErrorLogs = hasLogs);
    } catch (_) {
      if (!mounted) return;
      if (seq != _refreshSeq) return;

      setState(() => _hasErrorLogs = false);
    }
  }

  /// 로그 파일을 tail로 읽고, "에러로 볼 만한 흔적"이 있는지 판별
  Future<bool> _hasAnyErrorLog() async {
    final logger = DebugApiLogger();

    final List<String> lines = await logger.readTailLines(
      maxLines: 100,
      maxBytes: 64 * 1024,
    );

    return _detectErrorLogFromLines(lines);
  }

  /// JSON 형식이면서 level=error면 true.
  /// JSON이 아니거나 파싱 실패 라인은 "문제 로그로 간주"하여 true.
  bool _detectErrorLogFromLines(List<String> lines) {
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      try {
        final decoded = jsonDecode(line);

        if (decoded is Map<String, dynamic>) {
          final level = (decoded['level'] as String?)?.toLowerCase();
          if (level == 'error') return true;

          // level 정보는 없지만 JSON으로 남아있는 로그도 "문제 가능성"으로 볼지 정책 필요.
          // 현재는 기존 동작 유지: error가 아니면 continue.
          continue;
        }

        // JSON인데 Map이 아니면 구조 이상 → 에러로 간주
        return true;
      } catch (_) {
        // 파싱 실패 라인은 "손상/비정형" → 에러로 간주(기존 동작 유지)
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = _UpdateAlertTokens.of(
      context,
      updateBg: widget.background,
      updateFg: widget.foreground,
    );

    final logBg = _hasErrorLogs ? t.logErrBg : t.logOkBg;
    final logFg = _hasErrorLogs ? t.logErrFg : t.logOkFg;

    return Row(
      children: [
        Expanded(
          child: _SingleAlertBar(
            label: '업데이트',
            icon: Icons.new_releases_rounded,
            background: t.updateBg,
            foreground: t.updateFg,
            semanticsLabel: '업데이트',
            semanticsHint: '최신 업데이트 내용을 확인합니다',
            inkOverlay: t.inkOverlay,
            onTap: widget.onTapUpdate,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SingleAlertBar(
            label: '로그 확인',
            icon: Icons.bug_report_outlined,
            background: logBg,
            foreground: logFg,
            semanticsLabel: '로그 확인',
            semanticsHint: '디버그 로그를 확인합니다',
            inkOverlay: t.inkOverlay,
            onTap: () {
              widget.onTapLogs();

              // 시트 닫힘/렌더 이후 한 번 더 갱신(기존 의도 유지)
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _refreshLogStatus();
              });
            },
          ),
        ),
      ],
    );
  }
}

class _SingleAlertBar extends StatelessWidget {
  const _SingleAlertBar({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.semanticsLabel,
    required this.semanticsHint,
    required this.inkOverlay,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final String semanticsLabel;
  final String semanticsHint;

  /// InkWell overlay로 쓰는 미세 하이라이트
  final Color inkOverlay;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: semanticsLabel,
      hint: semanticsHint,
      child: Material(
        color: Colors.transparent, // M3 Ink 렌더링 위해 유지(표면색 하드코딩 아님)
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.pressed) ? inkOverlay : null,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: foreground,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
