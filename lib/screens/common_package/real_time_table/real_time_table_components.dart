import 'package:flutter/material.dart';

class RealTimeLockedPanel extends StatelessWidget {
  final String title;
  final String message;

  const RealTimeLockedPanel({
    super.key,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 44, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RealTimeExpandedLoading extends StatelessWidget {
  const RealTimeExpandedLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '데이터를 불러오는 중입니다…',
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class RealTimeExpandedEmpty extends StatelessWidget {
  final String message;

  const RealTimeExpandedEmpty({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: cs.outline),
            const SizedBox(height: 10),
            Text(
              '기록이 없습니다',
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RealTimePlateDetailNotFoundDialog extends StatelessWidget {
  final String plateId;
  final String viewPlateNumber;
  final String viewLocation;
  final String viewTimeText;

  const RealTimePlateDetailNotFoundDialog({
    super.key,
    required this.plateId,
    required this.viewPlateNumber,
    required this.viewLocation,
    required this.viewTimeText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '번호판 상세',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.close, color: cs.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.error.withOpacity(.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '원본 plates 문서를 찾을 수 없습니다.',
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'plateId: $plateId',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  'VIEW Plate: $viewPlateNumber',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  'VIEW Location: $viewLocation',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  'VIEW Time: $viewTimeText',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
