import 'package:flutter/material.dart';

class TutorialImageSplitPage extends StatelessWidget {
  final Widget Function(BuildContext) imageBuilder;
  final Widget Function(BuildContext)? zoomedImageBuilder;
  final bool enableImageZoom;
  final String title;
  final String desc;
  final Widget? footer;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry imageBorderRadius;
  final EdgeInsetsGeometry imagePadding;

  const TutorialImageSplitPage({
    super.key,
    required this.imageBuilder,
    required this.title,
    required this.desc,
    this.zoomedImageBuilder,
    this.enableImageZoom = true,
    this.footer,
    this.padding = const EdgeInsets.all(18),
    this.imageBorderRadius = const BorderRadius.all(Radius.circular(12)),
    this.imagePadding = EdgeInsets.zero,
  });

  Future<void> _openZoomDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final img = (zoomedImageBuilder ?? imageBuilder)(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 5.0,
                      child: Center(child: img),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: cs.onPrimary,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: padding,
      child: Column(
        children: [
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius: imageBorderRadius,
              child: Material(
                color: cs.surfaceContainerHighest,
                child: InkWell(
                  onTap: enableImageZoom ? () => _openZoomDialog(context) : null,
                  child: Padding(
                    padding: imagePadding,
                    child: Center(child: imageBuilder(context)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.center,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      desc,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: 14),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
