import 'package:flutter/material.dart';

class MinorSetDepartureRequestDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const MinorSetDepartureRequestDialog({super.key, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 24),
                  Row(
                    children: const [
                      Icon(Icons.directions_car, color: Colors.blueAccent, size: 28),
                      SizedBox(width: 8),
                      Text(
                        '출차 요청 확인',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '정말로 출차 요청을 진행하시겠습니까?',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onConfirm();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
