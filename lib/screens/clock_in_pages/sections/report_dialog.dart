import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';

class ParkingReportContent extends StatefulWidget {
  const ParkingReportContent({super.key});

  @override
  State<ParkingReportContent> createState() => _ParkingReportContentState();
}

class _ParkingReportContentState extends State<ParkingReportContent> {
  static const String _kakaoUrl = 'https://open.kakao.com/o/gU0jpLFh';

  /// 크롬으로 강제 열기
  Future<void> _launchKakaoChatWithChrome() async {
    final intent = AndroidIntent(
      action: 'action_view',
      data: _kakaoUrl,
      package: 'com.android.chrome',
    );

    try {
      await intent.launch();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('크롬으로 열 수 없습니다: $e')),
        );
      }
    }
  }

  /// url_launcher 기본 테스트
  Future<void> _launchFlutterDev() async {
    final Uri url = Uri.parse('https://flutter.dev');
    if (!await launchUrl(url, mode: LaunchMode.platformDefault)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('flutter.dev 링크를 열 수 없습니다.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 24,
        left: 16,
        right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '관리자 오픈 카톡방',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '출근 전 아래 버튼을 눌러 관리자에게 보고를 진행해주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.chat),
              label: const Text('크롬으로 카카오톡 열기'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
              onPressed: _launchKakaoChatWithChrome,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _launchFlutterDev,
              child: const Text('🌐 flutter.dev 열기 테스트'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
