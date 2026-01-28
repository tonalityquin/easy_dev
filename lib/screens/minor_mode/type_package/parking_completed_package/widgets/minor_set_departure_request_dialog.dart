import 'package:flutter/material.dart';

class MinorSetDepartureRequestDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const MinorSetDepartureRequestDialog({
    super.key,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Color surface = cs.surface;
    final Color onSurface = cs.onSurface;
    final Color onSurfaceVariant = cs.onSurfaceVariant;
    final Color border = cs.outlineVariant.withOpacity(0.85);

    // ✅ CTA는 브랜드 primary 사용
    final Color ctaBg = cs.primary;
    final Color ctaFg = cs.onPrimary;

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: DraggableScrollableSheet(
          initialChildSize: 0.4,
          minChildSize: 0.3,
          maxChildSize: 0.7,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border.all(color: border),
              ),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Icon(Icons.directions_car, color: cs.primary, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        '출차 요청 확인',
                        style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: onSurface,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Text(
                    '정말로 출차 요청을 진행하시겠습니까?',
                    style: (textTheme.bodyLarge ?? const TextStyle()).copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 32),

                  Center(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).maybePop();
                        onConfirm();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: ctaBg,
                        foregroundColor: ctaFg,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        textStyle: (textTheme.labelLarge ?? const TextStyle()).copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ).copyWith(
                        overlayColor: MaterialStateProperty.resolveWith<Color?>(
                              (states) => states.contains(MaterialState.pressed)
                              ? cs.primary.withOpacity(0.12)
                              : null,
                        ),
                      ),
                      child: const Text('확인'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
