import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/utils/snackbar_helper.dart';

class HeadquarterSupportActions {
  HeadquarterSupportActions._();

  static const String contactFormUrl = 'https://forms.gle/hDTkX1p6U9jMMuySA';
  static const String termsOfServiceUrl =
      'https://sites.google.com/view/parkinworkin3/%ED%99%88';
  static const String privacyPolicyUrl =
      'https://sites.google.com/view/parkinworkin4/%ED%99%88';

  static Future<bool> openTermsOfService([BuildContext? context]) {
    return _openExternalPage(
      url: termsOfServiceUrl,
      failureMessage: '이용약관 화면을 열 수 없습니다.',
      context: context,
    );
  }

  static Future<bool> openPrivacyPolicy([BuildContext? context]) {
    return _openExternalPage(
      url: privacyPolicyUrl,
      failureMessage: '개인정보보호처리방침 화면을 열 수 없습니다.',
      context: context,
    );
  }

  static Future<bool> openContactForm([BuildContext? context]) {
    return _openExternalPage(
      url: contactFormUrl,
      failureMessage: '문의하기 화면을 열 수 없습니다.',
      context: context,
    );
  }

  static Future<bool> _openExternalPage({
    required String url,
    required String failureMessage,
    BuildContext? context,
  }) async {
    final uri = Uri.parse(url);
    var opened = false;

    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }

    if (!opened) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        opened = false;
      }
    }

    if (!opened && context != null && context.mounted) {
      showFailedSnackbar(
        context,
        failureMessage,
        useCommonUi: true,
      );
    }

    debugPrint(
      '[HQ_SUPPORT][${DateTime.now().toIso8601String()}] external_page_open url=$url opened=$opened',
    );
    return opened;
  }
}
