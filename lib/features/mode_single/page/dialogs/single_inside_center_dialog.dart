import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';

Future<T?> showSingleInsideCenterDialog<T>({
  required BuildContext context,
  required String title,
  required IconData icon,
  required WidgetBuilder builder,
  Future<void> Function()? onDeveloperStatus,
  double maxWidth = 520,
  double maxHeightFactor = .86,
}) {
  return showCommonOverlayDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    builder: (dialogContext) {
      final tokens = CommonUiTheme.of(dialogContext);
      final media = MediaQuery.of(dialogContext);
      final availableWidth = media.size.width - 32;
      final width = availableWidth < maxWidth ? availableWidth : maxWidth;
      final maxHeight = media.size.height * maxHeightFactor;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: maxHeight,
          ),
          child: Material(
            color: tokens.surfaceRaised,
            surfaceTintColor: tokens.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
              side: BorderSide(color: tokens.borderSubtle),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: onDeveloperStatus == null
                      ? null
                      : () async {
                          await HapticFeedback.mediumImpact();
                          await onDeveloperStatus();
                        },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 8, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: tokens.surfaceSelected,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            icon,
                            size: 20,
                            color: tokens.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(dialogContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: tokens.borderSubtle),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: builder(dialogContext),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
