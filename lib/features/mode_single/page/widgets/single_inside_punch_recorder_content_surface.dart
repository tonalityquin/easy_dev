import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../application/single_inside_diagnostics.dart';
import 'widgets/single_inside_punch_recorder_section.dart';

class SingleInsidePunchRecorderContentSurface extends StatefulWidget {
  const SingleInsidePunchRecorderContentSurface({
    super.key,
    required this.active,
    required this.countdownRevision,
    required this.autoReturnDuration,
    required this.userId,
    required this.userName,
    required this.area,
    required this.division,
    required this.scheduleRevision,
    required this.onAutoReturn,
    required this.onDeveloperStatus,
  });

  final bool active;
  final int countdownRevision;
  final Duration autoReturnDuration;
  final String userId;
  final String userName;
  final String area;
  final String division;
  final int scheduleRevision;
  final VoidCallback onAutoReturn;
  final Future<void> Function() onDeveloperStatus;

  @override
  State<SingleInsidePunchRecorderContentSurface> createState() =>
      _SingleInsidePunchRecorderContentSurfaceState();
}

class _SingleInsidePunchRecorderContentSurfaceState
    extends State<SingleInsidePunchRecorderContentSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdownController;
  int _completedRevision = -1;

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: widget.autoReturnDuration,
    )..addStatusListener(_handleCountdownStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) return;
      _restartCountdown(source: 'screen_open');
    });
  }

  void _handleCountdownStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !widget.active) return;
    if (_completedRevision == widget.countdownRevision) return;
    _completedRevision = widget.countdownRevision;
    SingleInsideDiagnostics.log(
      'punch_content',
      'auto_return_completed target=dotMap revision=${widget.countdownRevision}',
    );
    widget.onAutoReturn();
  }

  void _restartCountdown({required String source}) {
    if (!widget.active) return;
    _completedRevision = -1;
    _countdownController
      ..stop()
      ..duration = widget.autoReturnDuration
      ..forward(from: 0);
    SingleInsideDiagnostics.log(
      'punch_content',
      'auto_return_scheduled source=$source delayMs=${widget.autoReturnDuration.inMilliseconds} revision=${widget.countdownRevision}',
    );
  }

  @override
  void didUpdateWidget(
    covariant SingleInsidePunchRecorderContentSurface oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _countdownController.stop();
      return;
    }
    if (!oldWidget.active ||
        oldWidget.countdownRevision != widget.countdownRevision ||
        oldWidget.autoReturnDuration != widget.autoReturnDuration) {
      _restartCountdown(
        source: oldWidget.active ? 'compact_rail' : 'workspace_enter',
      );
    }
  }

  @override
  void dispose() {
    _countdownController
      ..removeStatusListener(_handleCountdownStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: tokens.canvas,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () async {
              await HapticFeedback.mediumImpact();
              SingleInsideDiagnostics.log(
                'status',
                'developer_status_request source=punch_workspace_header',
              );
              await widget.onDeveloperStatus();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                '출퇴근 기록기',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: tokens.infoContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.info.withOpacity(.28)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: tokens.info,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '3초 뒤 주차 구역 표시로 되돌아갑니다',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      color: tokens.onInfoContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          AnimatedBuilder(
            animation: _countdownController,
            builder: (context, _) {
              final value =
                  (1 - _countdownController.value).clamp(0.0, 1.0).toDouble();
              return ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  value: value,
                  backgroundColor: tokens.infoContainer.withOpacity(.45),
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.info),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const ClampingScrollPhysics(),
                  child: SingleInsidePunchRecorderSection(
                    key: ValueKey<String>(
                      '${widget.userId}|${widget.division}|${widget.area}',
                    ),
                    userId: widget.userId,
                    userName: widget.userName,
                    area: widget.area,
                    division: widget.division,
                    scheduleRevision: widget.scheduleRevision,
                    embedded: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
