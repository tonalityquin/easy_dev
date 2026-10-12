import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../application/single_inside_diagnostics.dart';
import '../side_docks/single_inside_side_dock.dart';
import 'single_inside_hot_key_section.dart';
import 'widgets/single_inside_punch_recorder_section.dart';

class SingleInsidePunchRecorderContentSurface extends StatelessWidget {
  const SingleInsidePunchRecorderContentSurface({
    super.key,
    required this.userId,
    required this.userName,
    required this.area,
    required this.division,
    required this.scheduleRevision,
    required this.hotKeyRefreshRevision,
    required this.allowReports,
    required this.onHotKeyRequest,
    required this.onDeveloperStatus,
  });

  final String userId;
  final String userName;
  final String area;
  final String division;
  final int scheduleRevision;
  final int hotKeyRefreshRevision;
  final bool allowReports;
  final SingleInsideDashboardRequestHandler onHotKeyRequest;
  final Future<void> Function() onDeveloperStatus;

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
              await onDeveloperStatus();
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
          const SizedBox(height: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SingleInsidePunchRecorderSection(
                      key: ValueKey<String>('$userId|$division|$area'),
                      userId: userId,
                      userName: userName,
                      area: area,
                      division: division,
                      scheduleRevision: scheduleRevision,
                      embedded: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: tokens.borderSubtle,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: SizedBox.expand(
                        child: SingleInsideHotKeySection(
                          userId: userId,
                          division: division,
                          area: area,
                          allowReports: allowReports,
                          refreshRevision: hotKeyRefreshRevision,
                          onRequest: onHotKeyRequest,
                          onDeveloperStatus: onDeveloperStatus,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
