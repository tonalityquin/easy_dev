// lib/utils/external_openers.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

/// Gmail 수신함을 '외부 앱'으로 연다.
/// - ANDROID: Gmail 앱의 이메일 카테고리 인텐트로 수신함(앱 홈) 열기
/// - iOS: googlegmail 스킴으로 Gmail 앱 열기(보통 수신함)
/// - 실패 시: 기본 메일앱 → 마지막 폴백은 외부 브라우저의 Gmail 수신함
Future<void> openGmailInbox(BuildContext context) async {
  if (Platform.isAndroid) {
    // 1) Gmail 수신함(앱 홈) 열기: MAIN + APP_EMAIL 카테고리 + Gmail 패키지
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.APP_EMAIL',
        package: 'com.google.android.gm',
        flags: <int>[
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
          Flag.FLAG_ACTIVITY_CLEAR_TOP,
        ],
      );
      await intent.launch();
      return;
    } catch (_) {}

    // 2) (보조) 비공식 스킴 시도 — 기기/버전에 따라 미동작 가능
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: 'gmail://label/INBOX',
        package: 'com.google.android.gm',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return;
    } catch (_) {}

    // 3) (폴백) 기본 메일앱 수신함
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.APP_EMAIL',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return;
    } catch (_) {}
  } else if (Platform.isIOS) {
    // 4) iOS: Gmail 앱 자체 열기(대개 수신함으로 진입)
    try {
      final gmail = Uri.parse('googlegmail://');
      if (await canLaunchUrl(gmail)) {
        await launchUrl(gmail, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
  }

  // 5) 최종 폴백: 외부 브라우저에서 Gmail 수신함
  final inboxWeb = Uri.parse('https://mail.google.com/mail/u/0/#inbox');
  if (await canLaunchUrl(inboxWeb)) {
    await launchUrl(inboxWeb, mode: LaunchMode.externalApplication);
    return;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gmail 수신함을 열 수 없습니다.')),
    );
  }
}
