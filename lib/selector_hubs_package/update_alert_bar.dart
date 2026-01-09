// lib/screens/selector_hubs_package/update_alert_bar.dart
import 'dart:convert';

import 'package:flutter/material.dart';

import '../screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

class UpdateAlertBar extends StatefulWidget {
  const UpdateAlertBar({
    super.key,
    required this.onTapUpdate,
    required this.onTapLogs,
    this.background,
    this.foreground,
  });

  /// 기존 onTap 역할: 업데이트 바텀시트 열기 등
  final VoidCallback onTapUpdate;

  /// 새로 추가: 로그 확인(디버그 바텀시트 열기)
  final VoidCallback onTapLogs;

  final Color? background;
  final Color? foreground;

  @override
  State<UpdateAlertBar> createState() => _UpdateAlertBarState();
}

class _UpdateAlertBarState extends State<UpdateAlertBar> {
  bool _hasErrorLogs = false;

  @override
  void initState() {
    super.initState();
    _refreshLogStatus();
  }

  Future<void> _refreshLogStatus() async {
    try {
      final hasLogs = await _hasAnyErrorLog();
      if (!mounted) return;
      setState(() {
        _hasErrorLogs = hasLogs;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasErrorLogs = false;
      });
    }
  }

  /// ✅ API 로그(api_log.txt)에서 최근 일부 라인만 읽어서
  /// "level == error" 가 하나라도 있으면 true
  ///
  /// - Database / Local 로그는 제거(리팩터링 정책)
  Future<bool> _hasAnyErrorLog() async {
    final logger = DebugApiLogger();

    try {
      // 너무 많이 읽지 않도록 tail 기준으로만
      final List<String> lines = await logger.readTailLines(
        maxLines: 100,
        maxBytes: 64 * 1024,
      );

      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;

        // JSON 로그 포맷일 때
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, dynamic>) {
            final level = (decoded['level'] as String?)?.toLowerCase();
            if (level == 'error') return true;
            // info/other 로그면 스킵
            continue;
          } else {
            // Map이 아니더라도 내용이 있으면 "에러 존재"로 간주
            return true;
          }
        } catch (_) {
          // JSON 이 아니더라도, 내용이 있는 라인은 에러 로그로 간주
          return true;
        }
      }
    } catch (_) {
      // API 로거 실패 시에는 "에러 없음"으로 취급 (UI 안정성)
      return false;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 업데이트 버튼(좌측)은 기존 팔레트 유지
    final updateBg = widget.background ?? cs.primary;
    final updateFg = widget.foreground ?? cs.onPrimary;

    // 로그 버튼(우측)은 에러 로그 여부에 따라 초록/노랑
    final Color logBg;
    final Color logFg;

    if (_hasErrorLogs) {
      // 에러 존재 → 노란색 배경
      logBg = Colors.amber.shade600;
      logFg = Colors.black;
    } else {
      // 에러 없음 → 초록색 배경
      logBg = Colors.green.shade600;
      logFg = Colors.white;
    }

    return Row(
      children: [
        // 왼쪽 50% - 업데이트
        Expanded(
          child: _SingleAlertBar(
            label: '업데이트',
            icon: Icons.new_releases_rounded,
            background: updateBg,
            foreground: updateFg,
            semanticsLabel: '업데이트',
            semanticsHint: '최신 업데이트 내용을 확인합니다',
            onTap: widget.onTapUpdate,
          ),
        ),
        const SizedBox(width: 8),
        // 오른쪽 50% - 로그 확인 (동적 색상)
        Expanded(
          child: _SingleAlertBar(
            label: '로그 확인',
            icon: Icons.bug_report_outlined,
            background: logBg,
            foreground: logFg,
            semanticsLabel: '로그 확인',
            semanticsHint: '디버그 로그를 확인합니다',
            onTap: () {
              widget.onTapLogs();
              // 로그 시트에서 삭제/전송 등 작업 후 다시 들어오면 색 갱신
              WidgetsBinding.instance.addPostFrameCallback((_) {
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
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final String semanticsLabel;
  final String semanticsHint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: semanticsLabel,
      hint: semanticsHint,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
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
