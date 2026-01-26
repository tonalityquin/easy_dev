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

  final VoidCallback onTapUpdate;
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

  Future<bool> _hasAnyErrorLog() async {
    final logger = DebugApiLogger();

    try {
      final List<String> lines = await logger.readTailLines(
        maxLines: 100,
        maxBytes: 64 * 1024,
      );

      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;

        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, dynamic>) {
            final level = (decoded['level'] as String?)?.toLowerCase();
            if (level == 'error') return true;
            continue;
          } else {
            return true;
          }
        } catch (_) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final updateBg = widget.background ?? cs.primary;
    final updateFg = widget.foreground ?? cs.onPrimary;

    final Color logBg;
    final Color logFg;

    if (_hasErrorLogs) {
      logBg = cs.tertiaryContainer;
      logFg = cs.onTertiaryContainer;
    } else {
      logBg = cs.secondaryContainer;
      logFg = cs.onSecondaryContainer;
    }

    return Row(
      children: [
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
