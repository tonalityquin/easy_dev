// File: lib/utils/debug_tags.dart

/// 프로젝트 전반에서 DebugApiLogger(tags) 표준화를 위한 태그 정의.
/// - DebugBottomSheet의 tag 드롭다운 필터가 "정확 일치" 기반이므로
///   여기 문자열을 그대로 tags에 넣으면 즉시 필터링이 가능합니다.
/// - 네임스페이스 태그 예: "sheets/chat/*" 는 DebugBottomSheet에서 자동 생성됩니다.
class DebugTags {
  DebugTags._();

  // ─────────────────────────────────────────────────────────────
  // Namespace roots (선택적으로 함께 넣어두면 필터링 UX가 좋아짐)
  // ─────────────────────────────────────────────────────────────
  static const String sheets = 'sheets';
  static const String sheetsChat = 'sheets/chat';

  // ─────────────────────────────────────────────────────────────
  // SheetChatService
  // ─────────────────────────────────────────────────────────────
  static const String sheetsChatPoll = 'sheets/chat/poll';
  static const String sheetsChatSend = 'sheets/chat/send';
  static const String sheetsChatClear = 'sheets/chat/clear';
  static const String sheetsChatHeader = 'sheets/chat/header';
  static const String sheetsChatDelta = 'sheets/chat/delta';

  // (선택) GoogleAuth/Token
  static const String auth = 'auth';
  static const String authGoogle = 'auth/google';
  static const String authGoogleRefresh = 'auth/google/refresh';

  // (선택) Notification
  static const String noti = 'noti';
  static const String notiChat = 'noti/chat';

  /// tags에 넣을 “권장 기본 세트” 생성 헬퍼
  static List<String> setForSheetsChat(String leaf) {
    // leaf 예: sheets/chat/poll
    return <String>[leaf, sheetsChat, sheets];
  }
}
