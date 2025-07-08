import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../debugs/clock_in_debug_firestore_logger.dart'; // ✅ 로거 import

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
    final logger = ClockInDebugFirestoreLogger(); // ✅ 로거 인스턴스

    return ElevatedButton.icon(
      icon: const Icon(Icons.assignment),
      label: loadingUrl ? const Text('로딩 중...') : const Text('출근 보고-'),
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
        logger.log('🧲 [UI] 보고 작성 버튼 클릭됨', level: 'called');

        if (kakaoUrl == null || kakaoUrl!.isEmpty) {
          logger.log('🔥 카카오톡 URL이 null 또는 비어 있음', level: 'error');
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
          logger.log('🚀 크롬 Intent 실행 시도: $kakaoUrl', level: 'info');
          await intent.launch();
          logger.log('✅ 크롬으로 URL 열기 성공', level: 'success');
        } catch (e) {
          logger.log('🔥 크롬 실행 실패: $e', level: 'error');
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
