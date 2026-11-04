import 'package:flutter/foundation.dart';

import '../../features/selector/application/dev_auth.dart';

class SecureAuthDiagnostics {
  const SecureAuthDiagnostics._();

  static final List<String> _lines = <String>[];
  static List<String> get lines => List<String>.unmodifiable(_lines);

  static final RegExp _email = RegExp(
    r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
    caseSensitive: false,
  );
  static final RegExp _sensitiveValue = RegExp(
    r'\b(uid|firebaseUid|userId|idToken|accessToken|refreshToken|password|authorization|codeNumber|accountIdentifier|accountCode|secret|clientSecret|apiKey)\s*[:=]\s*[^\s,;}]+' ,
    caseSensitive: false,
  );
  static final RegExp _bearer = RegExp(
    r'Bearer\s+[A-Za-z0-9._\-]+',
    caseSensitive: false,
  );
  static final RegExp _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*',
  );
  static final RegExp _accountCode = RegExp(
    r'\b(?:\d{10,11}|(?=[a-z0-9]{11}\b)(?=[a-z0-9]*[a-z])(?=[a-z0-9]*\d)[a-z0-9]{11})\b',
    caseSensitive: false,
  );

  static String redact(String value) {
    final withoutBearer = value.replaceAll(_bearer, 'Bearer [비공개]');
    final withoutToken = withoutBearer.replaceAll(_jwt, '[토큰 비공개]');
    final withoutSensitive = withoutToken.replaceAllMapped(
      _sensitiveValue,
      (match) => '${match.group(1)}=[비공개]',
    );
    return withoutSensitive
        .replaceAll(_email, '[이메일 비공개]')
        .replaceAll(_accountCode, '[코드 비공개]');
  }

  static void record(String message) {
    if (!kDebugMode && !DevAuth.devModeEnabled.value) return;
    final safe = redact(message);
    _lines.add(safe);
    if (_lines.length > 300) {
      _lines.removeRange(0, _lines.length - 300);
    }
    debugPrint(safe);
  }
}
