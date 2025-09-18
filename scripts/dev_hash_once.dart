// scripts/dev_hash_once.dart
//
// 목적: "개발자만 아는 비밀 코드"를 소금(salt)과 함께 SHA-256으로 해싱해
//       앱에 하드코딩할 상수 2개(SALT_B64, HASH_HEX)를 출력합니다.
//       서버 없이, 오프라인으로 1회 생성만 하면 됩니다.
//
// 필요 의존성: pubspec.yaml 에 아래를 추가해 주세요.
// dependencies:
//   crypto: ^3.0.0
//
// 사용법(예시):
//   [A] 파일이 lib/scripts/dev_hash_once.dart 에 있을 때
//      1) 프로젝트 루트에서 실행:
//         dart run lib/scripts/dev_hash_once.dart --code="!!clover12"
//
//   - 인터랙티브 입력: 실행 후 프롬프트에 개발 코드를 입력(콘솔에 표시됨)
//   - 인자로 직접 전달:
//       --code="아주-긴-랜덤-개발-코드"
//   - 옵션:
//       --salt-bytes=16   : 솔트 바이트 길이(기본 16)
//       --verify          : 생성 직후 동일 코드 재입력해 일치 검증
//
// 출력 예시:
//   SALT_B64=2s3pJ8uY4lX5...==
//   HASH_HEX=3f4c9a...ab12
//
//   // 앱에 붙여넣을 상수:
//   const _DEV_SALT_B64 = '2s3pJ8uY4lX5...==';
//   const _DEV_HASH_HEX = '3f4c9a...ab12';
//
// 앱 쪽 검증 로직(요약):
//   final salt = base64Decode(_DEV_SALT_B64);
//   final bytes = <int>[]..addAll(salt)..addAll(utf8.encode(inputCode));
//   final digestHex = sha256.convert(bytes).toString();
//   비교: digestHex == _DEV_HASH_HEX (타이밍 안전 비교 권장)

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

void main(List<String> args) async {
  String? code;
  int saltLen = 16;
  bool verify = false;

  // 간단한 인자 파싱
  for (final a in args) {
    if (a.startsWith('--code=')) {
      code = a.substring('--code='.length);
    } else if (a.startsWith('--salt-bytes=')) {
      final v = int.tryParse(a.substring('--salt-bytes='.length));
      if (v != null && v > 0 && v <= 1024) {
        saltLen = v;
      } else {
        stderr.writeln('⚠️  --salt-bytes 값이 올바르지 않습니다. (1~1024)');
        exit(64);
      }
    } else if (a == '--verify') {
      verify = true;
    } else if (a == '--help' || a == '-h') {
      _printHelp();
      return;
    }
  }

  code ??= _ask('개발 코드 입력(콘솔에 그대로 보입니다, 주의): ');
  if (code == null || code.trim().isEmpty) {
    stderr.writeln('❌ 개발 코드가 비었습니다.');
    exit(64);
  }
  code = code.trim();

  final salt = _randomBytes(saltLen);
  final saltB64 = base64Encode(salt);
  final hashHex = _sha256Hex([...salt, ...utf8.encode(code)]);

  stdout.writeln('SALT_B64=$saltB64');
  stdout.writeln('HASH_HEX=$hashHex');
  stdout.writeln('\n// 앱에 붙여넣을 상수:');
  stdout.writeln("const _DEV_SALT_B64 = '$saltB64';");
  stdout.writeln("const _DEV_HASH_HEX = '$hashHex';");

  if (verify) {
    stdout.writeln('\n--verify 지정됨: 동일 코드 재입력하여 일치 검증을 진행합니다.');
    final again = _ask('다시 입력: ')?.trim() ?? '';
    final reHex = _sha256Hex([...salt, ...utf8.encode(again)]);
    final ok = _timingSafeEquals(hashHex, reHex);
    stdout.writeln(ok ? '✅ 일치합니다.' : '❌ 불일치합니다.');
  }
}

void _printHelp() {
  stdout.writeln('''
dev_hash_once.dart — 개발 코드 해시(SHA-256) 생성기

사용법:
  [루트에서 실행]
    dart run lib/scripts/dev_hash_once.dart [--code="비밀코드"] [--salt-bytes=16] [--verify]

  [lib/scripts 폴더에서 실행]
    dart run dev_hash_once.dart [--code="비밀코드"] [--salt-bytes=16] [--verify]

  [루트의 scripts/ 에 둘 경우]
    dart run scripts/dev_hash_once.dart [--code="비밀코드"] [--salt-bytes=16] [--verify]

옵션:
  --code="..."       개발 코드 직접 지정(미지정 시 인터랙티브 입력)
  --salt-bytes=16    솔트 길이(기본 16, 1~1024)
  --verify           생성 직후, 동일 코드 재입력 받아 일치 검증
  --help, -h         도움말

출력:
  SALT_B64=<Base64 솔트>
  HASH_HEX=<SHA-256 해시(헥사)>
  const _DEV_SALT_B64 = '...';
  const _DEV_HASH_HEX = '...';
''');
}

String? _ask(String prompt) {
  stdout.write(prompt);
  return stdin.readLineSync();
}

List<int> _randomBytes(int n) {
  final r = Random.secure();
  return List<int>.generate(n, (_) => r.nextInt(256));
}

String _sha256Hex(List<int> bytes) {
  final digest = sha256.convert(bytes);
  final b = StringBuffer();
  for (final v in digest.bytes) {
    b.write(v.toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// 타이밍 안전 비교(간단 버전)
bool _timingSafeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
