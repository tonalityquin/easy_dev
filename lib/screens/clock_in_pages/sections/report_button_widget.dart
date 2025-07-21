import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../debugs/clock_in_debug_firestore_logger.dart';

class ReportButtonWidget extends StatelessWidget {
  final bool loadingUrl;        // URL 로딩 중 여부
  final String? kakaoUrl;       // 보고용 카카오 URL
  final bool isDisabled;        // 추가: 외부에서 전체 버튼 비활성화 제어

  const ReportButtonWidget({
    super.key,
    required this.loadingUrl,
    required this.kakaoUrl,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final logger = ClockInDebugFirestoreLogger();

    final disabled = loadingUrl || isDisabled;

    return ElevatedButton.icon(
      icon: const Icon(Icons.report),
      label: Text(
        loadingUrl ? '로딩 중...' : '출근 보고',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: const BorderSide(color: Colors.grey, width: 1.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      onPressed: disabled
          ? null
          : () async {
        logger.log('🧲 [UI] 보고 작성 버튼 클릭됨', level: 'called');

        if (kakaoUrl == null || kakaoUrl!.isEmpty) {
          logger.log('🔥 카카오톡 URL이 null 또는 비어 있음', level: 'error');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('카카오톡 URL이 없습니다.')),
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
              SnackBar(content: Text('크롬으로 열 수 없습니다: $e')),
            );
          }
        }
      },
    );
  }
}
