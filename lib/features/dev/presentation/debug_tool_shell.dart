import 'package:flutter/material.dart';

class DebugToolHeader extends StatelessWidget {
  const DebugToolHeader({
    super.key,
    required this.title,
    required this.breadcrumb,
    required this.onClose,
    required this.onStatus,
    required this.onDebugExit,
    this.onBack,
    this.meta,
    this.actions = const <Widget>[],
  });

  static const Color debugAccent = Color(0xFF6D5DFB);

  final String title;
  final String breadcrumb;
  final String? meta;
  final VoidCallback? onBack;
  final VoidCallback onClose;
  final VoidCallback onStatus;
  final VoidCallback onDebugExit;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.8)),
            ),
          ),
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: '뒤로',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              else
                const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: debugAccent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: debugAccent.withOpacity(0.45),
                            ),
                          ),
                          child: const Text(
                            'DEBUG',
                            style: TextStyle(
                              color: debugAccent,
                              fontFamily: 'monospace',
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      breadcrumb,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (meta != null && meta!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ...actions,
              PopupMenuButton<String>(
                tooltip: 'DEBUG 도구',
                onSelected: (value) {
                  if (value == 'status') onStatus();
                  if (value == 'exit_debug') onDebugExit();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem<String>(
                    value: 'status',
                    child: Row(
                      children: [
                        Icon(Icons.monitor_heart_outlined),
                        SizedBox(width: 10),
                        Text('Status'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'exit_debug',
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded),
                        SizedBox(width: 10),
                        Text('DEBUG 종료'),
                      ],
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_vert_rounded),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
