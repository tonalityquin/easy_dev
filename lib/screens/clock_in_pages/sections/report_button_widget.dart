import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';

class ReportButtonWidget extends StatelessWidget {
  final bool loadingUrl;
  final String? kakaoUrl;

  const ReportButtonWidget({
    super.key,
    required this.loadingUrl,
    required this.kakaoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.assignment),
      label: loadingUrl ? const Text('로딩 중...') : const Text('보고 작성'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: Colors.grey),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: loadingUrl
          ? null
          : () async {
        if (kakaoUrl == null || kakaoUrl!.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('카카오톡 URL이 없습니다.'),
            ),
          );
          return;
        }
        final intent = AndroidIntent(
          action: 'action_view',
          data: kakaoUrl!,
          package: 'com.android.chrome',
        );
        try {
          await intent.launch();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('크롬으로 열 수 없습니다: $e'),
              ),
            );
          }
        }
      },
    );
  }
}
