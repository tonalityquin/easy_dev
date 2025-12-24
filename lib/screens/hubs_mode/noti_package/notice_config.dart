import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/api/sheets_config.dart';

/// ✅ 공지 스프레드시트 저장 키 (SharedPreferences)
const String kNoticeSpreadsheetIdKey = 'notice_spreadsheet_id_v1';

/// ✅ (중요) 공지 시트명 고정: noti
const String kNoticeSheetName = 'noti';

/// ✅ (중요) 공지 Range (noti 시트 A열 1~50행)
const String kNoticeSpreadsheetRange = '$kNoticeSheetName!A1:A50';

/// ✅ 공지 고정 행 수
const int kNoticeMaxRows = 50;

/// 공지 스프레드시트 ID 변경을 앱 전역에서 공유하기 위한 노티파이어
final ValueNotifier<String> noticeSheetIdNotifier = ValueNotifier<String>('');

/// 공지 내용이 저장/변경되었음을 알리는 revision 노티파이어
/// - Header/공지 카드가 “ID 변경”이 아닌 “내용 변경”에도 자동 갱신되게 하려면 이를 listen 하면 됩니다.
final ValueNotifier<int> noticeRevisionNotifier = ValueNotifier<int>(0);

bool _bootstrapped = false;

/// 앱 실행 후 1회만 SharedPreferences로부터 공지 스프레드시트 ID를 로드
Future<void> ensureNoticeBootstrapped() async {
  if (_bootstrapped) return;
  _bootstrapped = true;

  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(kNoticeSpreadsheetIdKey) ?? '').trim();
    noticeSheetIdNotifier.value = saved;
  } catch (_) {
    // 부트스트랩 실패는 치명적이지 않으므로 묵살
  }
}

/// 현재 공지 스프레드시트 ID
String get currentNoticeSheetId => noticeSheetIdNotifier.value.trim();

/// 공지 스프레드시트 ID 저장(입력값이 URL이면 ID 추출)
Future<String> setNoticeSheetId(String rawOrUrl) async {
  final prefs = await SharedPreferences.getInstance();
  final id = SheetsConfig.extractSpreadsheetId(rawOrUrl.trim()).trim();

  if (id.isEmpty) {
    await prefs.remove(kNoticeSpreadsheetIdKey);
    noticeSheetIdNotifier.value = '';
    return '';
  }

  await prefs.setString(kNoticeSpreadsheetIdKey, id);
  noticeSheetIdNotifier.value = id;
  return id;
}

/// 공지 스프레드시트 ID 초기화
Future<void> clearNoticeSheetId() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kNoticeSpreadsheetIdKey);
  noticeSheetIdNotifier.value = '';
}

/// 공지 내용 갱신(revision bump)
void bumpNoticeRevision() {
  noticeRevisionNotifier.value = noticeRevisionNotifier.value + 1;
}
