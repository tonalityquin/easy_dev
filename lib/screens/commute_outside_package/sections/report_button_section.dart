import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../../../utils/snackbar_helper.dart';

class ReportButtonSection extends StatelessWidget {
  final bool loadingUrl;
  final String? kakaoUrl;
  final bool isDisabled;

  const ReportButtonSection({
    super.key,
    required this.loadingUrl,
    required this.kakaoUrl,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {

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

        if (kakaoUrl == null || kakaoUrl!.isEmpty) {
          // 🔁 기본 SnackBar → 커스텀 스낵바
          showFailedSnackbar(context, '카카오톡 URL이 없습니다.');
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
            // 🔁 기본 SnackBar → 커스텀 스낵바
            showFailedSnackbar(context, '크롬으로 열 수 없습니다: $e');
          }
        }
      },
    );
  }
}
