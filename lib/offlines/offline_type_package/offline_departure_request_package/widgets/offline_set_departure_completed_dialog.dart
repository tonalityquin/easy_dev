import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OfflineSetDepartureCompletedDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const OfflineSetDepartureCompletedDialog({
    super.key,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.redAccent, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        '출차 완료 확인',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '정말로 출차 완료 처리를 하시겠습니까?',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: '출차 완료 처리 확인',
                          child: FilledButton(
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              Navigator.pop(context);
                              Future.microtask(onConfirm);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('확인'),
                          ),
                        ),
                      ),
                    ],
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
