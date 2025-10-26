// lib/screens/dev_package/dev_memo.dart
//
// ※ intl 패키지가 필요합니다. pubspec.yaml에 추가하세요:
// dependencies:
//   intl: ^0.19.0
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show LogicalKeySet, Intent; // ✅ [2] 명시 import
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_navigator.dart';
import '../../utils/google_auth_session.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis/drive/v3.dart' as drive;

import '../../utils/email_config.dart';

/// DevMemo (싱글 문서 모드)
class DevMemo {
  DevMemo._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  // ---- SharedPreferences Keys ----
  static const _kDocKey = 'dev_memo_doc_md_v1';

  // Drive 캐시 키 (레거시 단일 문서용 포함)
  static const _kDriveFolderId = 'dev_memo_drive_folder_id_v1';
  static const _kDriveFileId = 'dev_memo_drive_file_id_v1';

  // ✅ 추가: 현재 선택 파일명 및 파일ID 맵 캐시 키
  static const _kDriveSelectedFileName = 'dev_memo_drive_selected_file_v1';
  static const _kDriveFileIdMap = 'dev_memo_drive_file_id_map_v1';

  // Drive 이름 상수
  static const String kDriveFolderName = '00.IdeaNote';        // ✅ 새 폴더명
  static const String kDriveLegacyFolderName = 'DevMemo';   // ⬅️ 과거 폴더명(있으면 자동 개명)
  static const String kDriveFileName = '00.IdeaNote.md';       // ✅ 새 파일명(디폴트)
  static const String kDriveLegacyFileName = 'DevMemo.md';  // ⬅️ 과거 파일명(있으면 자동 개명)

  // ✅ 하드코딩 파일 후보(요청 반영)
  static const List<String> kDriveCandidateNames = [
    kDriveFileName,     // 'IdeaNote.md'
    '00.TodoList.md',
    '01.plan.md',
    '02.background.md',
    '03.character.md',
  ];

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  static Future<void> togglePanel() async {
    final ctx = _bestContext();
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => togglePanel());
      return;
    }

    await showModalBottomSheet(
      context: ctx,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DevMemoSheet(),
    );
  }

  static Future<void> openPanel() => togglePanel();
}

class _DevMemoSheet extends StatefulWidget {
  const _DevMemoSheet();

  @override
  State<_DevMemoSheet> createState() => _DevMemoSheetState();
}

class _DevMemoSheetState extends State<_DevMemoSheet> {
  final TextEditingController _docCtrl = TextEditingController();
  final FocusNode _docFocus = FocusNode();
  final ScrollController _scrollCtrl = ScrollController(); // ✅ 스크롤바 컨트롤러
  bool _sending = false;

  bool _driveBusy = false;
  Timer? _saveDebounce;

  // ✅ 현재 선택된 파일명(디폴트 IdeaNote.md) 및 파일ID 캐시 맵
  String _currentFileName = DevMemo.kDriveFileName;
  Map<String, String> _fileIdCache = {}; // filename -> fileId

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _docCtrl.addListener(_onDocChanged);
  }

  Future<void> _loadInitial() async {
    final prefs = DevMemo._prefs ?? await SharedPreferences.getInstance();
    final text = prefs.getString(DevMemo._kDocKey) ?? '';
    _docCtrl.text = text;

    // ✅ 현재 선택 파일명 & 파일ID 맵 복원
    _currentFileName = prefs.getString(DevMemo._kDriveSelectedFileName) ?? DevMemo.kDriveFileName;
    final mapJson = prefs.getString(DevMemo._kDriveFileIdMap);
    if (mapJson != null) {
      try {
        final m = json.decode(mapJson) as Map<String, dynamic>;
        _fileIdCache = m.map((k, v) => MapEntry(k, v as String));
      } catch (_) {}
    }
  }

  void _onDocChanged() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _persistDoc);
  }

  Future<void> _persistDoc() async {
    final prefs = DevMemo._prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(DevMemo._kDocKey, _docCtrl.text);
  }

  Future<void> _persistFileIdCache() async {
    final prefs = DevMemo._prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(DevMemo._kDriveFileIdMap, json.encode(_fileIdCache));
  }

  Future<void> _persistSelectedFileName() async {
    final prefs = DevMemo._prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(DevMemo._kDriveSelectedFileName, _currentFileName);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _docCtrl.removeListener(_onDocChanged);
    _docCtrl.dispose();
    _docFocus.dispose();
    _scrollCtrl.dispose(); // ✅ ScrollController 해제
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final shortcuts = <ShortcutActivator, Intent>{
      // 인라인 코드
      LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.backquote): const _MdIntent(_MdCmd.inlineCode),
      LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.backquote): const _MdIntent(_MdCmd.inlineCode),
      LogicalKeySet(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.backquote): const _MdIntent(_MdCmd.inlineCode),
      LogicalKeySet(LogicalKeyboardKey.metaRight, LogicalKeyboardKey.backquote): const _MdIntent(_MdCmd.inlineCode),

      // 체크박스
      LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.keyC):
      const _MdIntent(_MdCmd.checkbox),
      LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.keyC):
      const _MdIntent(_MdCmd.checkbox),
      LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.keyC):
      const _MdIntent(_MdCmd.checkbox),
      LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.keyC):
      const _MdIntent(_MdCmd.checkbox),
      LogicalKeySet(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.keyC):
      const _MdIntent(_MdCmd.checkbox),
      LogicalKeySet(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.keyC):
      const _MdIntent(_MdCmd.checkbox),
      LogicalKeySet(LogicalKeyboardKey.metaRight, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.keyC):
      const _MdIntent(_MdCmd.checkbox),
      LogicalKeySet(LogicalKeyboardKey.metaRight, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.keyC):
      const _MdIntent(_MdCmd.checkbox),

      // 토글 블록
      LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.keyT):
      const _MdIntent(_MdCmd.toggleBlock),
      LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.keyT):
      const _MdIntent(_MdCmd.toggleBlock),
      LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.keyT):
      const _MdIntent(_MdCmd.toggleBlock),
      LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.keyT):
      const _MdIntent(_MdCmd.toggleBlock),
      LogicalKeySet(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.keyT):
      const _MdIntent(_MdCmd.toggleBlock),
      LogicalKeySet(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.keyT):
      const _MdIntent(_MdCmd.toggleBlock),
      LogicalKeySet(LogicalKeyboardKey.metaRight, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.keyT):
      const _MdIntent(_MdCmd.toggleBlock),
      LogicalKeySet(LogicalKeyboardKey.metaRight, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.keyT):
      const _MdIntent(_MdCmd.toggleBlock),

      // 굵게/기울임
      LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyB): const _MdIntent(_MdCmd.bold),
      LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.keyB): const _MdIntent(_MdCmd.bold),
      LogicalKeySet(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyB): const _MdIntent(_MdCmd.bold),
      LogicalKeySet(LogicalKeyboardKey.metaRight, LogicalKeyboardKey.keyB): const _MdIntent(_MdCmd.bold),

      LogicalKeySet(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyI): const _MdIntent(_MdCmd.italic),
      LogicalKeySet(LogicalKeyboardKey.controlRight, LogicalKeyboardKey.keyI): const _MdIntent(_MdCmd.italic),
      LogicalKeySet(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyI): const _MdIntent(_MdCmd.italic),
      LogicalKeySet(LogicalKeyboardKey.metaRight, LogicalKeyboardKey.keyI): const _MdIntent(_MdCmd.italic),
    };

    return FractionallySizedBox(
      heightFactor: 1.0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Material(
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Shortcuts(
                shortcuts: shortcuts,
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _MdIntent: CallbackAction<_MdIntent>(
                      onInvoke: (intent) {
                        switch (intent.cmd) {
                          case _MdCmd.inlineCode:
                            _insertInlineCode();
                            break;
                          case _MdCmd.checkbox:
                            _insertCheckbox();
                            break;
                          case _MdCmd.toggleBlock:
                            _insertToggleBlock();
                            break;
                          case _MdCmd.bold:
                            _wrapSelection('**', '**', '굵게');
                            break;
                          case _MdCmd.italic:
                            _wrapSelection('*', '*', '기울임');
                            break;
                        }
                        return null;
                      },
                    ),
                  },
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      const _DragHandle(),
                      const SizedBox(height: 12),

                      // 헤더
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(Icons.sticky_note_2_rounded, color: cs.primary),
                            const SizedBox(width: 8),
                            // ✅ 현재 파일명 표시
                            Text(
                              _currentFileName,
                              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const Spacer(),

                            // ✅ 파일 선택/변경 Dialog
                            IconButton(
                              tooltip: '파일 선택/변경(.md)',
                              onPressed: _driveBusy ? null : _openChooseFileDialog,
                              icon: const Icon(Icons.drive_file_rename_outline),
                            ),

                            // Drive 불러오기(현재 선택 파일)
                            IconButton(
                              tooltip: _driveBusy ? '불러오는 중...' : 'Drive에서 불러오기',
                              onPressed: _driveBusy ? null : _driveLoad,
                              icon: _driveBusy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.cloud_download_outlined),
                            ),
                            // Drive 저장(현재 선택 파일)
                            IconButton(
                              tooltip: _driveBusy ? '저장 중...' : 'Drive에 저장',
                              onPressed: _driveBusy ? null : _driveSave,
                              icon: _driveBusy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.cloud_upload_outlined),
                            ),

                            // 이메일 전송(.md 첨부)
                            IconButton(
                              tooltip: _sending ? '전송 중...' : '이메일로 보내기(.md)',
                              onPressed: _sending ? null : _sendAsMarkdownByEmail,
                              icon: _sending
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.email_outlined),
                            ),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),

                      // MD 툴바
                      _MdToolbar(
                        onInlineCode: _insertInlineCode,
                        onCheckbox: _insertCheckbox,
                        onToggleBlock: _insertToggleBlock,
                        onBold: () => _wrapSelection('**', '**', '굵게'),
                        onItalic: () => _wrapSelection('*', '*', '기울임'),
                        onH1: () => _toggleHeadingAcrossSelection('# '),
                        onH2: () => _toggleHeadingAcrossSelection('## '),
                        onBullet: () => _togglePrefixAcrossSelection('- '),
                        onNumbered: () => _togglePrefixAcrossSelection('1. '),
                        onQuote: () => _togglePrefixAcrossSelection('> '),
                        onLink: () => _insertTemplate('[텍스트](https://example.com)'),
                        onImage: () {}, // 제거됨
                        onTable: () {}, // 제거됨
                      ),

                      // 에디터 (✅ Scrollbar + scrollController 연결)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          child: Scrollbar(
                            controller: _scrollCtrl,
                            thumbVisibility: true,  // 항상 보이게
                            trackVisibility: true,  // 트랙도 보이게(옵션)
                            thickness: 6,           // 두께(옵션)
                            radius: const Radius.circular(8),
                            interactive: true,
                            child: TextField(
                              controller: _docCtrl,
                              focusNode: _docFocus,
                              scrollController: _scrollCtrl, // ✅ 연결
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              maxLines: null,
                              minLines: null,
                              expands: true,
                              // ✅ 입력 왜곡 방지
                              textCapitalization: TextCapitalization.none,
                              smartDashesType: SmartDashesType.disabled,
                              smartQuotesType: SmartQuotesType.disabled,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                height: 1.4,
                              ),
                              decoration: InputDecoration(
                                hintText: '여기에 마크다운 문서를 작성하세요.\n예) # 제목\n- [ ] 작업 항목\n`인라인 코드`',
                                filled: true,
                                fillColor: cs.surfaceVariant.withOpacity(.3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.2)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.2)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: cs.primary, width: 1.4),
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _prepareEdit() {
    if (!_docFocus.hasFocus) {
      _docFocus.requestFocus();
    }
    if (!_docCtrl.selection.isValid) {
      final end = _docCtrl.text.length;
      _docCtrl.selection = TextSelection.collapsed(offset: end);
    }
  }

  // ---------- 이메일 전송(.md 첨부) ----------
  Future<void> _sendAsMarkdownByEmail() async {
    final text = _docCtrl.text.trim();
    if (text.isEmpty) {
      _showSnack('보낼 내용이 없습니다.');
      return;
    }

    final cfg = await EmailConfig.load();
    if (!EmailConfig.isValidToList(cfg.to)) {
      _showSnack('수신자(To) 설정이 필요합니다: 설정 화면에서 이메일을 입력하세요.');
      return;
    }

    setState(() => _sending = true);
    try {
      final now = DateTime.now();
      final subject = 'DevMemo export (${DateFormat('yyyy-MM-dd').format(now)})';
      final filename = 'dev_memo_${DateFormat('yyyyMMdd_HHmmss').format(now)}.md';
      final normalized = text.replaceAll('\r\n', '\n');

      final boundary = 'devmemo_md_${now.millisecondsSinceEpoch}';
      final bodyText = '첨부된 마크다운(.md) 파일에 문서가 포함되어 있습니다.';
      final toCsv = cfg.to;

      final attachmentB64 = base64.encode(utf8.encode(normalized));

      final mime = StringBuffer()
        ..writeln('MIME-Version: 1.0')
        ..writeln('To: $toCsv')
        ..writeln('Subject: $subject')
        ..writeln('Content-Type: multipart/mixed; boundary="$boundary"')
        ..writeln()
        ..writeln('--$boundary')
        ..writeln('Content-Type: text/plain; charset="utf-8"')
        ..writeln('Content-Transfer-Encoding: 7bit')
        ..writeln()
        ..writeln(bodyText)
        ..writeln()
        ..writeln('--$boundary')
        ..writeln('Content-Type: text/markdown; charset="utf-8"; name="$filename"')
        ..writeln('Content-Disposition: attachment; filename="$filename"')
        ..writeln('Content-Transfer-Encoding: base64')
        ..writeln()
        ..writeln(attachmentB64)
        ..writeln('--$boundary--');

      final raw = base64Url.encode(utf8.encode(mime.toString()));

      final client = await GoogleAuthSession.instance.client();
      final api = gmail.GmailApi(client);
      final message = gmail.Message()..raw = raw;

      await api.users.messages.send(message, 'me');

      _showSnack('이메일을 보냈습니다(.md 첨부).');
    } catch (e) {
      _showSnack('전송 실패: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }

  // ---------- MD 편집 도우미 ----------
  void _insertInlineCode() {
    _prepareEdit();
    _wrapSelection('`', '`', 'code');
  }

  void _insertCheckbox() {
    _prepareEdit();
    _togglePrefixAcrossSelection('- [ ] ');
  }

  void _insertToggleBlock() {
    _prepareEdit();
    const template = '''
<details>
<summary>제목</summary>

내용

</details>
''';
    _insertTemplate(template.trimRight() + '\n');
  }

  void _wrapSelection(String prefix, String suffix, String placeholder) {
    _prepareEdit();

    final sel = _docCtrl.selection;
    final text = _docCtrl.text;

    final start = sel.start;
    final end = sel.end;
    final hasSelection = !sel.isCollapsed;

    final selected = hasSelection ? text.substring(start, end) : '';
    final middle = selected.isEmpty ? placeholder : selected;

    final replaced = '$prefix$middle$suffix';
    _replaceRange(start, end, replaced,
        newSelection: hasSelection
            ? TextSelection(baseOffset: start, extentOffset: start + replaced.length)
            : TextSelection.collapsed(offset: start + prefix.length + middle.length));
  }

  void _togglePrefixAcrossSelection(String prefix) {
    _prepareEdit();

    final text = _docCtrl.text;
    final sel = _docCtrl.selection;

    final startLine = _lineStartIndex(text, sel.start);
    final endLine = _lineEndIndex(text, sel.end);

    final block = text.substring(startLine, endLine);
    final lines = block.split('\n');

    final updatedLines = lines.map((l) {
      final line = l;
      if (line.startsWith(prefix)) {
        return line.substring(prefix.length);
      } else if (line.trim().isEmpty) {
        return prefix;
      } else {
        return prefix + line;
      }
    }).toList();

    final updated = updatedLines.join('\n');
    _replaceRange(
      startLine,
      endLine,
      updated,
      newSelection: TextSelection.collapsed(offset: startLine + updated.length),
    );
  }

  void _toggleHeadingAcrossSelection(String marker) {
    _prepareEdit();

    final text = _docCtrl.text;
    final sel = _docCtrl.selection;

    final startLine = _lineStartIndex(text, sel.start);
    final endLine = _lineEndIndex(text, sel.end);

    final block = text.substring(startLine, endLine);
    final lines = block.split('\n');

    final headingRegex = RegExp(r'^\s{0,3}#{1,6}\s+');

    final updatedLines = lines.map((l) {
      final stripped = l.replaceFirst(headingRegex, '');
      if (l.startsWith(marker)) {
        return stripped;
      } else {
        return '$marker${stripped.trimLeft()}';
      }
    }).toList();

    final updated = updatedLines.join('\n');
    _replaceRange(
      startLine,
      endLine,
      updated,
      newSelection: TextSelection.collapsed(offset: startLine + updated.length),
    );
  }

  void _insertTemplate(String snippet) {
    _prepareEdit();
    final sel = _docCtrl.selection;
    _replaceRange(sel.start, sel.end, snippet,
        newSelection: TextSelection.collapsed(offset: sel.start + snippet.length));
  }

  void _replaceRange(int start, int end, String replacement, {TextSelection? newSelection}) {
    final text = _docCtrl.text;
    final newText = text.replaceRange(start, end, replacement);
    _docCtrl.value = _docCtrl.value.copyWith(
      text: newText,
      selection: newSelection ?? TextSelection.collapsed(offset: start + replacement.length),
      composing: TextRange.empty,
    );
    HapticFeedback.selectionClick();
  }

  int _lineStartIndex(String text, int index) {
    if (index <= 0) return 0;
    final i = text.lastIndexOf('\n', index - 1);
    return (i == -1) ? 0 : i + 1;
  }

  int _lineEndIndex(String text, int index) {
    if (index < 0) return text.length;
    final i = text.indexOf('\n', index);
    return (i == -1) ? text.length : i;
  }

  // ========== Google Drive 연동 (강화 + 폴더명 마이그레이션) ==========

  Future<drive.DriveApi> _driveApi() async {
    final client = await GoogleAuthSession.instance.client();
    return drive.DriveApi(client);
  }

  Future<void> _clearDriveIdCache() async {
    final prefs = DevMemo._prefs ?? await SharedPreferences.getInstance();
    await prefs.remove(DevMemo._kDriveFolderId);
    await prefs.remove(DevMemo._kDriveFileId);    // 레거시 단일 문서 캐시
    await prefs.remove(DevMemo._kDriveFileIdMap); // ✅ 추가된 맵 캐시 제거
    await prefs.remove(DevMemo._kDriveSelectedFileName); // ✅ 선택 파일명 캐시 제거
  }

  Future<String?> _validateId(
      drive.DriveApi api,
      String? id, {
        required bool expectFolder,
      }) async {
    if (id == null) return null;
    try {
      // ✅ 타입 안전화
      final resp = await api.files.get(id, $fields: 'id,mimeType,trashed');
      if (resp is! drive.File) return null;
      final file = resp;

      if (file.trashed == true) return null;
      if (expectFolder && file.mimeType != 'application/vnd.google-apps.folder') return null;
      if (!expectFolder && file.mimeType == 'application/vnd.google-apps.folder') return null;
      return file.id;
    } catch (_) {
      // 404 등: 무효
      return null;
    }
  }

  Future<String> _ensureFolder(drive.DriveApi api, String? cachedId) async {
    // 1) 캐시 유효성 검증
    final validCached = await _validateId(api, cachedId, expectFolder: true);
    if (validCached != null) return validCached;

    // 2) 새 이름(IdeaNote)으로 검색 (최근 생성 1개)
    final qNew =
        "mimeType = 'application/vnd.google-apps.folder' and name = '${DevMemo.kDriveFolderName}' and trashed = false";
    final resNew = await api.files.list(
      q: qNew,
      $fields: 'files(id,name,createdTime)',
      spaces: 'drive',
      orderBy: 'createdTime desc',
    );
    if (resNew.files != null && resNew.files!.isNotEmpty) {
      return resNew.files!.first.id!;
    }

    // 3) 과거 이름(DevMemo) 검색 후 있으면 폴더를 IdeaNote로 개명
    final qOld =
        "mimeType = 'application/vnd.google-apps.folder' and name = '${DevMemo.kDriveLegacyFolderName}' and trashed = false";
    final resOld = await api.files.list(
      q: qOld,
      $fields: 'files(id,name,createdTime)',
      spaces: 'drive',
      orderBy: 'createdTime desc',
    );
    if (resOld.files != null && resOld.files!.isNotEmpty) {
      final legacyId = resOld.files!.first.id!;
      final meta = drive.File()..name = DevMemo.kDriveFolderName;
      final updated = await api.files.update(meta, legacyId);
      return updated.id!;
    }

    // 4) 없으면 새로 생성
    final meta = drive.File()
      ..name = DevMemo.kDriveFolderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await api.files.create(meta);
    return created.id!;
  }

  Future<List<drive.File>> _listAllMarkdownInFolder(
      drive.DriveApi api,
      String folderId,
      ) async {
    final files = <drive.File>[];
    String? pageToken;
    final q = "'$folderId' in parents and trashed = false and name contains '.md'";

    do {
      final resp = await api.files.list(
        q: q,
        $fields: 'nextPageToken, files(id,name,mimeType,modifiedTime)',
        spaces: 'drive',
        orderBy: 'modifiedTime desc',
        pageToken: pageToken,
      );
      if (resp.files != null) files.addAll(resp.files!);
      pageToken = resp.nextPageToken;
    } while (pageToken?.isNotEmpty ?? false); // ✅ 불필요한 '!' 제거

    return files;
  }

  // ========== 파일 선택/변경 Dialog ==========
  Future<void> _openChooseFileDialog() async {
    if (_driveBusy) return;
    final ctx = context;
    final api = await _driveApi();

    // 폴더 보장
    final prefs = DevMemo._prefs ?? await SharedPreferences.getInstance();
    String? folderId = await _validateId(api, prefs.getString(DevMemo._kDriveFolderId), expectFolder: true);
    folderId = await _ensureFolder(api, folderId);
    await prefs.setString(DevMemo._kDriveFolderId, folderId);

    // 폴더 내 .md + 하드코딩 후보 합치기
    final driveFiles = await _listAllMarkdownInFolder(api, folderId);
    final namesInDrive = driveFiles.map((f) => f.name ?? '').where((s) => s.isNotEmpty);
    final nameSet = <String>{...DevMemo.kDriveCandidateNames, ...namesInDrive};

    // 현재 파일명을 맨 앞으로, 나머지는 알파벳 정렬
    final items = nameSet.toList();
    items.sort((a, b) {
      if (a == _currentFileName && b != _currentFileName) return -1;
      if (b == _currentFileName && a != _currentFileName) return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    String selected = _currentFileName;

    await showDialog(
      context: ctx,
      builder: (dctx) {
        return StatefulBuilder(
          builder: (dctx, setStateDialog) {
            return AlertDialog(
              title: const Text('불러올 파일 선택(.md)'),
              content: SizedBox(
                width: 380,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final name = items[i];
                    return RadioListTile<String>(
                      title: Text(name),
                      value: name,
                      groupValue: selected,
                      onChanged: (v) {
                        if (v == null) return;
                        setStateDialog(() => selected = v);
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('취소')),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(dctx);
                    if (!mounted) return;
                    setState(() => _currentFileName = selected);
                    await _persistSelectedFileName();
                    await _driveLoadSelected(selected);
                  },
                  child: const Text('열기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ========== 선택 파일 불러오기/저장 ==========
  Future<void> _driveLoadSelected(String filename, {bool retry = true}) async {
    setState(() => _driveBusy = true);
    try {
      final prefs = DevMemo._prefs ?? await SharedPreferences.getInstance();
      final api = await _driveApi();

      // 폴더 ID 유효성 검증 + 보장(DevMemo → IdeaNote 로직 유지)
      String? folderId = await _validateId(api, prefs.getString(DevMemo._kDriveFolderId), expectFolder: true);
      folderId = await _ensureFolder(api, folderId);
      await prefs.setString(DevMemo._kDriveFolderId, folderId);

      // 파일 ID 캐시 확인 → 유효성 검증
      String? fileId = _fileIdCache[filename];
      fileId = await _validateId(api, fileId, expectFolder: false);

      // 캐시가 무효면 폴더 내 같은 이름 검색
      if (fileId == null) {
        final q = "'$folderId' in parents and name = '$filename' and trashed = false";
        final r = await api.files.list(q: q, $fields: 'files(id,name,modifiedTime)');
        if (r.files != null && r.files!.isNotEmpty) {
          fileId = r.files!.first.id!;
        } else {
          // 디폴트 파일명일 때만 레거시(DevMemo.md → IdeaNote.md) 마이그레이션
          if (filename == DevMemo.kDriveFileName) {
            final qOld = "'$folderId' in parents and name = '${DevMemo.kDriveLegacyFileName}' and trashed = false";
            final rOld = await api.files.list(q: qOld, $fields: 'files(id,name,modifiedTime)');
            if (rOld.files != null && rOld.files!.isNotEmpty) {
              final legacyId = rOld.files!.first.id!;
              final meta = drive.File()..name = DevMemo.kDriveFileName;
              final updated = await api.files.update(meta, legacyId);
              fileId = updated.id!;
            }
          }
        }
      }

      // 파일이 있으면 다운로드, 없으면 에디터 비우고 안내
      if (fileId != null) {
        final dl = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia);
        if (dl is! drive.Media) throw Exception('Unexpected download response');
        final bytes = await _readAllBytes(dl.stream);
        final text = utf8.decode(bytes);

        _docCtrl.text = text;
        _docCtrl.selection = TextSelection.collapsed(offset: _docCtrl.text.length);

        _fileIdCache[filename] = fileId; // 캐시에 반영
        await _persistFileIdCache();

        _showSnack('Drive에서 "$filename"을(를) 불러왔습니다.');
      } else {
        _docCtrl.clear();
        _showSnack('"$filename" 문서를 찾지 못했습니다. 저장하면 새로 생성됩니다.');
      }

      // 현재 파일명 고정 및 저장
      if (_currentFileName != filename) {
        setState(() => _currentFileName = filename);
        await _persistSelectedFileName();
      }
    } catch (e) {
      final msg = e.toString();
      if (retry && (msg.contains('404') || msg.contains('notFound'))) {
        await _clearDriveIdCache();
        await _driveLoadSelected(filename, retry: false);
      } else {
        _showSnack('Drive 불러오기 실패: $e');
      }
    } finally {
      if (mounted) setState(() => _driveBusy = false);
    }
  }

  Future<void> _driveSaveSelected(String filename, {bool retry = true}) async {
    setState(() => _driveBusy = true);
    try {
      final prefs = DevMemo._prefs ?? await SharedPreferences.getInstance();
      final api = await _driveApi();

      // 폴더 보장
      String? folderId = await _validateId(api, prefs.getString(DevMemo._kDriveFolderId), expectFolder: true);
      folderId = await _ensureFolder(api, folderId);
      await prefs.setString(DevMemo._kDriveFolderId, folderId);

      // 파일ID 캐시 확인
      String? fileId = _fileIdCache[filename];
      fileId = await _validateId(api, fileId, expectFolder: false);

      // 본문 준비
      final content = _docCtrl.text.replaceAll('\r\n', '\n');
      final bytes = utf8.encode(content);
      final media = drive.Media(Stream<List<int>>.fromIterable([bytes]), bytes.length);
      const mime = 'text/markdown';

      if (fileId == null) {
        // 같은 이름 있는지 재검색
        final q = "'$folderId' in parents and name = '$filename' and trashed = false";
        final r = await api.files.list(q: q, $fields: 'files(id,name,modifiedTime)', orderBy: 'modifiedTime desc');
        if (r.files != null && r.files!.isNotEmpty) {
          fileId = r.files!.first.id!;
        } else {
          // 없으면 새로 생성
          final meta = drive.File()
            ..name = filename
            ..mimeType = mime
            ..parents = [folderId];
          final created = await api.files.create(meta, uploadMedia: media);
          fileId = created.id!;
          _fileIdCache[filename] = fileId;
          await _persistFileIdCache();
          _showSnack('Drive에 "$filename"을(를) 새로 저장했습니다.');
          return;
        }
      }

      // 존재하면 업데이트
      final meta = drive.File()..mimeType = mime;
      await api.files.update(meta, fileId, uploadMedia: media);
      _fileIdCache[filename] = fileId;
      await _persistFileIdCache();
      _showSnack('"$filename"을(를) 업데이트했습니다.');
    } catch (e) {
      final msg = e.toString();
      if (retry && (msg.contains('404') || msg.contains('notFound') || msg.contains('File not found') || msg.contains('Parent'))) {
        await _clearDriveIdCache();
        await _driveSaveSelected(filename, retry: false);
      } else {
        _showSnack('Drive 저장 실패: $e');
      }
    } finally {
      if (mounted) setState(() => _driveBusy = false);
    }
  }

  // ---------- 기존 단일 API → 현재 선택 파일로 위임 ----------
  Future<void> _driveLoad({bool retry = true}) => _driveLoadSelected(_currentFileName, retry: retry);
  Future<void> _driveSave({bool retry = true}) => _driveSaveSelected(_currentFileName, retry: retry);

  // ---------- 바이트 읽기 유틸 ----------
  Future<Uint8List> _readAllBytes(Stream<List<int>> stream) async {
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }
}

// ---------- widgets ----------

class _MdToolbar extends StatelessWidget {
  final VoidCallback onInlineCode;
  final VoidCallback onCheckbox;
  final VoidCallback onToggleBlock;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onH1;
  final VoidCallback onH2;
  final VoidCallback onBullet;
  final VoidCallback onNumbered;
  final VoidCallback onQuote;
  final VoidCallback onLink;
  final VoidCallback onImage;
  final VoidCallback onTable;

  const _MdToolbar({
    required this.onInlineCode,
    required this.onCheckbox,
    required this.onToggleBlock,
    required this.onBold,
    required this.onItalic,
    required this.onH1,
    required this.onH2,
    required this.onBullet,
    required this.onNumbered,
    required this.onQuote,
    required this.onLink,
    required this.onImage,
    required this.onTable,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _ttIcon(context, Icons.code_rounded, '인라인 코드 (Ctrl/Cmd+`)', onInlineCode),
          _ttIcon(context, Icons.check_box_outlined, '체크박스 (Ctrl/Cmd+Shift+C)', onCheckbox),
          _ttIcon(context, Icons.expand_more_rounded, '토글 블록 (Ctrl/Cmd+Shift+T)', onToggleBlock),
          _ttIcon(context, Icons.format_bold_rounded, '굵게 (Ctrl/Cmd+B)', onBold),
          _ttIcon(context, Icons.format_italic_rounded, '기울임 (Ctrl/Cmd+I)', onItalic),
          _chip(context, 'H1', onH1, cs.primary),
          _chip(context, 'H2', onH2, cs.secondary),
          _ttIcon(context, Icons.format_list_bulleted_rounded, '불릿 목록', onBullet),
          _ttIcon(context, Icons.format_list_numbered_rounded, '번호 목록', onNumbered),
          _ttIcon(context, Icons.format_quote_rounded, '인용문', onQuote),
          _ttIcon(context, Icons.link_rounded, '링크', onLink),
        ],
      ),
    );
  }

  Widget _ttIcon(BuildContext context, IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, VoidCallback onTap, Color bg) {
    final on = Theme.of(context).colorScheme.onPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: on)),
      ),
    );
  }
}

/// ✅ 드래그 핸들(그립 바)
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 5,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

// ---------- 키맵용 인텐트 ----------
enum _MdCmd { inlineCode, checkbox, toggleBlock, bold, italic }

class _MdIntent extends Intent {
  final _MdCmd cmd;
  const _MdIntent(this.cmd);
}
